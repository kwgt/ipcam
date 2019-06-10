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

  class << self
    def start
      restore_db()

      @mutex   = Mutex.new
      @camera  = nil
      @state   = :READY
      @img_que = Thread::Queue.new
      @cam_thr = Thread.new {camera_thread}
      @snd_thr = Thread.new {sender_thread}
      @clients = []

      WebServer.start(self)
      WebSocket.start(self)

      EM.run
    end

    def stop
      @cam_thr.join

      @snd_thr.raise(Stop)
      @snd_thr.join


      WebServer.stop
      EM.stop
    end

    def restart_camera
      @cam_thr.raise(Stop)
      @cam_thr.join

      @img_que.clear

      @cam_thr = Thread.new {camera_thread}
    end

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
        blob  = $db_file.binread
        @db   = MessagePack.unpack(blob, :symbolize_keys => true)

      rescue
        begin
          $db_file.delete
        rescue Errno::ENOENT
          # ignore
        end
          
        @db   = {}
      end
    end
    private :restore_db

    def load_settings
      ret = @db.dig(@camera.bus, @camera.name)

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

    def camera_thread
      $logger.info("main") {"camera thread start"}

      @mutex.synchronize {
        @camera = Video4Linux2::Camera.new($target)

        if not @camera.support_formats.any? {|x| x.fcc == "MJPG"}
          raise("#{$target} is not support Motion-JPEG")
        end

        @config = load_settings()

        @camera.start
        @state = :BUSY
      }

      loop {
        @img_que << @camera.capture
      }

    rescue Stop
      $logger.info("main") {"accept stop request"}
      @state = :READY

    rescue => e
      $logger.error("main") {"camera error occured (#{e.message})"}
      @state = :ABORTED

    ensure
      @camera&.stop if @camera&.busy?
      @camera&.close
      @camera = nil

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
      $logger.info("main") {"accept stop request"}
      @clients.each {|c| c[:que] << nil}

    ensure
      $logger.info("main") {"sender thread stop"}
    end

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
      raise("state violation") if @state != :BUSY
      return "#{@camera.name}@#{@camera.bus}"
    end

    def get_config
      raise("state violation") if @state != :BUSY
      return @config
    end

    def set_image_size(width, height)
      raise("state violation") if @state != :BUSY

      @mutex.synchronize {
        @config[:image_width]  = width
        @config[:image_height] = height
      }

      restart_camera()
      broadcast(:update_image_size, width, height)
    end

    def set_framerate(num, deno)
      raise("state violation") if @state != :BUSY

      @mutex.synchronize {
        @config[:framerate] = [num, deno]
      }

      restart_camera()
      broadcast(:update_framerate, num, deno)
    end

    def set_control(id, val)
      raise("state violation") if @state != :BUSY

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
      @mutex.synchronize {
        $db_file.binwrite(@db.to_msgpack)
      }
    end

    def add_client(que)
      @clients << {:que => que}
    end

    def remove_client(que)
      @clients.reject! {|c| c[:que] == que}
    end
  end
end
