#! /usr/bin/env ruby
# coding: utf-8

#
# Sample for v4l2-ruby
#
#   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'sinatra/base'
require 'sinatra/streaming'
require 'puma'
require 'puma/configuration'
require 'puma/events'
require 'eventmachine'
require 'securerandom'

module IPCam
  class WebServer < Sinatra::Base
    set :environment, (($develop_mode)? %s{development}: %s{production})
    set :views, APP_RESOURCE_DIR + "views"
    set :threaded, true
    set :quiet, true

    enable :logging

    use Rack::CommonLogger, $logger

    configure :development do
      before do
        cache_control :no_store, :no_cache, :must_revalidate,
                      :max_age => 0, :post_check => 0, :pre_check => 0
        headers "Pragma" => "no-cache"
      end
    end

    helpers do
      def app
        return (@app ||= settings.app)
      end

      def find_resource(type, name)
        ret = RESOURCE_DIR + "extern" + type + name
        return ret if ret.exist?

        ret = RESOURCE_DIR + "common" + type + name
        return ret if ret.exist?

        ret = APP_RESOURCE_DIR + type + name
        return ret if ret.exist?

        return nil
      end
    end

    get "/" do
      redirect "/main"
    end

    get "/main" do
      erb :main
    end

    get "/settings" do
      erb :settings
    end

    get "/stream" do
      halt 500 if app.abort?
      halt 404 if app.stop?

      boundary = SecureRandom.hex(20)
      queue    = Thread::Queue.new

      content_type("multipart/x-mixed-replace; boundary=#{boundary}")

      # pumaで:keep_openが動作しないのでちょっと面倒な方法で
      # 対応
      stream do |port|
        port.callback {
          app.remove_client(queue)
          queue.clear
          queue << nil
        }

        port << "\r\n"
        app.add_client(queue)

        loop {
          data = queue.deq
          break if not data

          port << <<~EOT.b
            --#{boundary}
            Content-Type: image/jpeg\r
            Content-Length: #{data.bytesize}\r
            \r
          EOT

          port << data

          # データ詰まりを防ぐ為にキューをクリア
          queue.clear
        }
      end
    end

    get %r{/css/(.+).scss} do |name|
      content_type('text/css')
      scss name.to_sym, :views => APP_RESOURCE_DIR + "scss"
    end

    get %r{/(css|js|img|fonts)/(.+)} do |type, name|
      path = find_resource(type, name)
      
      if path
        send_file(path)
      else
        halt 404
      end
    end

    class << self
      def bind_url
        if $bind_addr.include?(":")
          addr = "[#{$bind_addr}]" if $bind_addr.include?(":")
        else
          addr = $bind_addr
        end

        return "tcp://#{addr}:#{$http_port}"
      end
      private :bind_url

      def env_string
        return ($develop_mode)? 'development':'production'
      end

      def start(app)
        set :app, app

        config  = Puma::Configuration.new { |user_config|
          user_config.quiet
          user_config.threads(4, 4)
          user_config.bind(bind_url())
          user_config.environment(env_string())
          user_config.force_shutdown_after(-1)
          user_config.app(WebServer)
        }

        @events = Puma::Events.new($log_device, $log_device)
        @launch = Puma::Launcher.new(config, :events => @events)

        # pumaのランチャークラスでのシグナルのハンドリングが
        # 邪魔なのでオーバライドして無効化する
        def @launch.setup_signals
          # nothing
        end

        @thread = Thread.start {
          begin
            $logger.info('webserver') {"started #{bind_url()}"}
            @launch.run
          ensure
            $logger.info('webserver') {"stopped"}
          end
        }

        # サーバが立ち上がりきるまで待つ
        booted  = false
        @events.on_booted {booted = true}
        sleep 0.2 until booted
      end

      def stop
        @launch.stop
        @thread.join

        remove_instance_variable(:@launch)
        remove_instance_variable(:@thread)
      end
    end
  end
end
