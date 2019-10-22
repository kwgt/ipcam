#! /usr/bin/env ruby
# coding: utf-8

#
# Sample for v4l2-ruby
#
#   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'sinatra/base'
require 'puma'
require 'puma/configuration'
require 'puma/events'
require 'eventmachine'
require 'securerandom'
require 'digest/md5'

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

      def websock_url
        return "#{($use_ssl)? "wss":"ws"}://${location.hostname}:#{$ws_port}"
      end
    end

    get "/" do
      redirect "/main"
    end

    get "/js/const.js" do
      content_type("text/javascript")

      <<~EOS
        const WEBSOCK_URL = `#{websock_url}`; 
      EOS
    end

    get "/main" do
      erb :main
    end

    get "/settings" do
      erb :settings
    end

    head "/stream" do
      halt 500 if app.abort?
      halt 404 if app.stop?
      halt 503 if not env["rack.hijack?"]

      headers = {
        "Content-Type" =>"multipart/x-mixed-replace;",
        "Connection"   => "close",
      }

      [200, headers, nil]
    end

    get "/stream" do
      halt 500 if app.abort?
      halt 404 if app.stop?
      halt 503 if not env["rack.hijack?"]

      boundary = SecureRandom.hex(20)
      queue    = Thread::Queue.new
      headers  = {
        "Content-Type"   =>"multipart/x-mixed-replace; boundary=#{boundary}",
        "Connection"     => "close",

        # Rackのhijack API経由で生ソケットを用いてストリーミングを行う
        "rack.hijack"    => -> (sock) {
          begin
            app.add_client(queue)

            if sock.kind_of?(TCPSocket)
              sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_QUICKACK, 1)
              sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
            end

            sock.write("\r\n".b)
            sock.flush

            fc = 0

            loop {
              body = queue.deq
              break if not body

              if $extend_header
                header = <<~EOT.b
                  --#{boundary}\r
                  Content-Type: image/jpeg\r
                  Content-Length: #{body.bytesize}\r
                  X-Frame-Number: #{fc}\r
                  X-Timestamp: #{(Time.now.to_f * 1000).round}\r
                  \r
                EOT
              else
                header = <<~EOT.b
                  --#{boundary}\r
                  Content-Type: image/jpeg\r
                  Content-Length: #{body.bytesize}\r
                  \r
                EOT
              end

              sock.write(header)
              sock.write(body)
              sock.flush
              fc += 1

              # データ詰まりを防ぐ為にキューをクリア
              queue.clear
            }

          rescue
            # ignore

          ensure
            sock.close

            app.remove_client(queue)
            queue.clear
          end
        }
      }

      # ↓力業でsinatraがContent-Lengthを付与するのを抑止している
      def response.calculate_content_length?
        return false
      end

      [200, headers, nil]
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
      if $use_dauth
        def new(*)
          ret = Rack::Auth::Digest::MD5.new(super) {|user| $passwd_db[user]}

          ret.realm            = TRADITIONAL_NAME
          ret.opaque           = SecureRandom.alphanumeric(32)
          ret.passwords_hashed = true

          return ret
        end

        def make_a1_string(user, pass)
          return Digest::MD5.hexdigest("#{user}:#{TRADITIONAL_NAME}:#{pass}")
        end
        private :make_a1_string

        def add_user(user, pass)
          $passwd_db[user] = make_a1_string(user, pass)

          $passwd_file.open("w") { |f|
            f.chmod(0o600)
            f.write($passwd_db.to_yaml)
          }
        end
      end

      def bind_url
        if $bind_addr.include?(":")
          addr = "[#{$bind_addr}]" if $bind_addr.include?(":")
        else
          addr = $bind_addr
        end

        if $use_ssl
          ret = "ssl://#{addr}:#{$http_port}?key=#{$ssl_key}&cert=#{$ssl_cert}"
        else
          ret = "tcp://#{addr}:#{$http_port}"
        end

        return ret
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
