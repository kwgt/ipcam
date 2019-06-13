#! /usr/bin/env ruby
# coding: utf-8

#
# Sample for v4l2-ruby
#
#   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'v4l2'
require 'msgpack'

module IPCam
  BASIS_SIZE = 640 * 480
  Stop       = Class.new(Exception)
  Restart    = Class.new(Exception)

  class << self
    def start
      restore_db()

      @mutex   = Mutex.new
      @camera  = nil
      @state   = :STOP
      @img_que = Thread::Queue.new
      @clients = []

      start_thread()

      WebServer.start(self)
      WebSocket.start(self)

      EM.run
    end

    def stop
      stop_thread()

      WebServer.stop
      EM.stop
    end

    def start_thread
      @cam_thr = Thread.new {camera_thread}
    end
    private :start_thread

    def stop_thread
      @cam_thr.raise(Stop)
      @cam_thr.join
      @cam_thr = nil
    end
    private :stop_thread

    def restart_camera
      @cam_thr.raise(Restart)
    end
    private :restart_camera

    def select_capabilities(cam)
      ret = cam.frame_capabilities(:MJPEG).instance_eval {
        self.sort! { |a,b|
          da = (BASIS_SIZE - (a.width * a.height)).abs
          db = (BASIS_SIZE - (b.width * b.height)).abs

          da <=> db
        }

        self.first
      }

      return ret
    end
    private :select_capabilities

    def pack_capability(cap)
      ret = {
        :width  => cap.width,
        :height => cap.height,
        :rate   => cap.rate.inject([]) { |m, n|
          m << [n.numerator, n.denominator]
        }
      }

      return ret
    end
    private :pack_capability

    def create_capability_list(cam)
      ret = cam.frame_capabilities(:MJPEG).inject([]) { |m, n|
        m << pack_capability(n)
      }

      return ret
    end
    private :create_capability_list

    def pack_integer_control(c)
      ret = {
        :type  => :integer,
        :id    => c.id,
        :name  => c.name,
        :value => c.default,
        :min   => c.min,
        :max   => c.max,
        :step  => c.step
      }

      return ret
    end
    private :pack_integer_control

    def pack_boolean_control(c)
      ret = {
        :type  => :boolean,
        :id    => c.id,
        :name  => c.name,
        :value => c.default
      }

      return ret
    end
    private :pack_boolean_control

    def pack_menu_control(c)
      ret = {
        :type  => :menu,
        :id    => c.id,
        :name  => c.name,
        :value => c.default,
        :items => c.items.inject({}) {|m, n| m[n.name] = n.index; m}
      }

      return ret
    end
    private :pack_menu_control

    def create_control_list(cam)
      ret = cam.controls.inject([]) { |m, n|
        case n
        when Video4Linux2::Camera::IntegerControl
          m << pack_integer_control(n)

        when Video4Linux2::Camera::BooleanControl
          m << pack_boolean_control(n)

        when Video4Linux2::Camera::MenuControl
          m << pack_menu_control(n)

        else
          raise("Unknwon control found #{n.class}")
        end
      }

      return ret
    end
    private :create_control_list

    def create_setting_entry(cam)
      cap  = select_capabilities(cam)
      rate = cap.rate.sort.first

      ret  = {
        :image_width  => cap.width,
        :image_height => cap.height,
        :framerate    => [rate.numerator, rate.denominator],
        :capabilities => create_capability_list(cam),
        :controls     => create_control_list(cam)
      }

      return ret
    end
    private :create_setting_entry

    def restore_db
      begin
        blob = $db_file.binread
        @db  = MessagePack.unpack(blob, :symbolize_keys => true)

        @db.keys { |bus|
          @db[bus].keys { |name|
            @db[bus][name.to_s] = @db[bus].delete(name)
          }

          @db[bus.to_s] = @db.deleye(bus)
        }

      rescue
        begin
          $db_file.delete
        rescue Errno::ENOENT
          # ignore
        end
          
        @db  = {}
      end
    end
    private :restore_db

    def load_settings
      ret = @db.dig(@camera.bus.to_sym, @camera.name.to_sym)

      if not ret
        ret = create_setting_entry(@camera)
        (@db[@camera.bus] ||= {})[@camera.name] = ret

        $db_file.binwrite(@db.to_msgpack)
      end

      @camera.image_height = ret[:image_height]
      @camera.image_width  = ret[:image_width]
      @camera.framerate    = Rational(*ret[:framerate])

      ret[:controls].each { |ctr|
        @camera.set_control(ctr[:id], ctr[:value]) rescue :ignore
      }

      return ret
    end
    private :load_settings

    def broadcast(name, *args)
      WebSocket.broadcast(name, *args)
    end
    private :broadcast

    def change_state(state)
      flag = @mutex.try_lock

      if @state != state
        @state = state
        broadcast(:change_state, state)
      end

      @mutex.unlock if flag
    end
    private :change_state

    def camera_thread
      $logger.info("main") {"camera thread start"}

      @camera = Video4Linux2::Camera.new($target)
      if not @camera.support_formats.any? {|x| x.fcc == "MJPG"}
        raise("#{$target} is not support Motion-JPEG")
      end

      snd_thr = Thread.new {sender_thread}

      begin
        @mutex.synchronize {
          @config = load_settings()

          @camera.start
          change_state(:ALIVE)
        }

        loop {
          @img_que << @camera.capture
        }

      rescue Stop
        $logger.info("main") {"accept stop request"}
        change_state(:STOP)

      rescue Restart
        $logger.info("main") {"restart camera"}
        @camera.stop
        retry

      rescue => e
        change_state(:ABORT)
        raise(e)

      ensure
        @camera.stop if (@camera.busy? rescue false)
      end

    rescue => e
      $logger.error("main") {"camera error occured (#{e.message})"}
      change_state(:ABORT)

    ensure
      @camera&.close
      @camera = nil

      snd_thr&.raise(Stop)
      snd_thr&.join

      $logger.info("main") {"camera thread stop"}
    end
    private :camera_thread

    def sender_thread
      $logger.info("main") {"sender thread start"}

      loop {
        data = @img_que.deq
        @clients.each {|c| c[:que] << data}
        broadcast(:update_image, {:type => "image/jpeg", :data => data})
      }

    rescue Stop
      @clients.each {|c| c[:que] << nil}

    ensure
      $logger.info("main") {"sender thread stop"}
    end
    private:sender_thread

    def get_camera_info
      @mutex.synchronize {
        ret = {
          :device => $target,
          :state  => @state
        }

        ret.merge!(:bus => @camera.bus, :name => @camera.name) if @camera

        return ret
      }
    end

    def get_ident_string
      raise("state violation") if @state != :ALIVE
      return "#{@camera.name}@#{@camera.bus}"
    end

    def get_config
      raise("state violation") if @state != :ALIVE
      return @config
    end

    def set_image_size(width, height)
      raise("state violation") if @state != :ALIVE

      @mutex.synchronize {
        @config[:image_width]  = width
        @config[:image_height] = height
      }

      restart_camera()
      broadcast(:update_image_size, width, height)
    end

    def set_framerate(num, deno)
      raise("state violation") if @state != :ALIVE

      @mutex.synchronize {
        @config[:framerate] = [num, deno]
      }

      restart_camera()
      broadcast(:update_framerate, num, deno)
    end

    def set_control(id, val)
      raise("state violation") if @state != :ALIVE

      entry = nil

      @mutex.synchronize {
        entry = @config[:controls].find {|obj| obj[:id] == id} 
        entry[:value] = val if entry
      }

      if entry
        restart_camera()
        broadcast(:update_control, id, val)
      end
    end

    def save_config
      $logger.info('main') {"save config to #{$db_file.to_s}"}
      @mutex.synchronize {
        $db_file.binwrite(@db.to_msgpack)
      }

      broadcast(:save_complete)
    end

    def add_client(que)
      @clients << {:que => que}
    end

    def remove_client(que)
      @clients.reject! {|c| c[:que] == que}
    end

    def start_camera
      raise("state violation") if @state != :STOP and @state != :ABORT

      start_thread()
    end

    def stop_camera
      raise("state violation") if @state != :ALIVE

      stop_thread()
    end

    def alive?
      @state == :ALIVE
    end

    def abort?
      @state == :ABORT
    end

    def stop?
      @state == :STOP
    end
  end
end
