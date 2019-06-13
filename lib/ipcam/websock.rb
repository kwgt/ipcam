#! /usr/bin/env ruby
# coding: utf-8

#
# Sample for v4l2-ruby
#
#   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'fileutils'
require 'em-websocket'
require 'msgpack/rpc/server'

module IPCam
  class WebSocket
    include MessagePack::Rpc::Server

    msgpack_options :symbolize_keys => true

    class << self
      #
      # セッションリストの取得
      #
      # @return [Array<WebSocket>] セッションリスト
      #
      def session_list
        return @session_list ||= []
      end
      private :session_list

      #
      # クリティカルセクションの設置
      #
      # @yield クリティカルセクションとして処理するブロック
      #
      # @return [Object] ブロックの戻り値
      #
      def sync(&proc)
        return (@mutex ||= Mutex.new).synchronize(&proc)
      end

      #
      # セッションリストへのセッション追加
      #
      # @param [Socket] sock  セッションリストに追加するソケットオブジェクト
      #
      # @return [WebSocket]
      #   ソケットオブジェクトに紐付けられたセッションオブジェクト
      #
      # @note
      #   受け取ったソケットオブジェクトを元に、セッションオブジェクトを
      #   生成し、そのオブジェクトをセッションリストに追加する
      #
      def join(sock)
        sync {
          if session_list.any? {|s| s === sock}
            raise("Already joined #{sock}")
          end

          ret = self.new(@app, sock)
          session_list << ret

          return ret
        }
      end
      private :join

      #
      # セッションオブジェクトからのセッション削除
      #
      # @param [Socket] sock
      #   セッションオブジェクトを特定するためのソケットオブジェクト
      #
      def bye(sock)
        sync {
          session_list.reject! { |s|
            if s === sock
              s.finish
              true
            else
              false
            end
          }
        }
      end

      #
      # イベント情報の一斉送信
      #
      # @param [String] name  イベント名
      # @param [Array] args イベントで通知する引数
      #
      def broadcast(name, *args)
        sync {session_list.each {|s| s.notify(name, *args)}}
      end

      #
      # バインド先のURL文字列を生成する
      #
      # @return [String] URL文字列
      #
      def bind_url
        if $bind_addr.include?(":")
          addr = "[#{$bind_addr}]" if $bind_addr.include?(":")
        else
          addr = $bind_addr
        end

        return "tcp://#{addr}:#{$ws_port}"
      end
      private :bind_url

      #
      # WebSocket制御の開始
      #
      def start(app)
        EM.defer {
          @app = app

          sleep 1 until EM.reactor_running?

          $logger.info("websock") {"started (#{bind_url()})"}

          EM::WebSocket.start(:host => $bind_addr, :port => $ws_port) { |sock|
            peer = Socket.unpack_sockaddr_in(sock.get_peername)
            addr = peer[1]
            port = peer[0]
            serv = join(sock)

            sock.set_sock_opt(Socket::Constants::SOL_SOCKET,
                              Socket::SO_KEEPALIVE,
                              true)

            sock.set_sock_opt(Socket::IPPROTO_TCP,
                              Socket::TCP_QUICKACK,
                              true)

            sock.set_sock_opt(Socket::IPPROTO_TCP,
                              Socket::TCP_NODELAY,
                              false)

            sock.onopen {
              $logger.info("websock") {"connection from #{addr}:#{port}"}
            }

            sock.onbinary { |msg|
              begin
                serv.receive_dgram(msg)

              rescue => e
                $logger.error("websock") {
                  "error occured: #{e.message} (#{e.backtrace[0]})"
                }
              end
            }

            sock.onclose {
              $logger.info("websock") {
                "connection close from #{addr}:#{port}"
              }

              bye(sock)
            }
          }
        }
      end
    end

    #
    # セッションオブジェクトのイニシャライザ
    #
    # @param [IPCam] app  アプリケーション本体のインスタンス
    # @param [Socket] sock Socketインスタンス
    #
    def initialize(app, sock)
      @app   = app
      @sock  = sock
      @allow = []

      peer   = Socket.unpack_sockaddr_in(sock.get_peername)
      @addr  = peer[1]
      @port  = peer[0]
    end

    attr_reader :sock

    #
    # セッションオブジェクトの終了処理
    #
    def finish
    end

    #
    # peerソケットへのデータ送信
    #
    # @param [String] data  送信するデータ
    #
    # @note MessagePack::Rpc::Serverのオーバーライド
    #
    def send_data(data)
      @sock.send_binary(data)
    end
    private :send_data

    #
    # MessagePack-RPCのエラーハンドリング
    #
    # @param [StandardError] e  発生したエラーの例外オブジェクト
    #
    # @note MessagePack::Rpc::Serverのオーバーライド
    # 
    def on_error(e)
      $logger.error("websock") {e.message}
    end
    private :on_error

    #
    # 通知のブロードキャスト
    #
    # @param [String] name  イベント名
    # @param [Array] args イベントで通知する引数
    #
    def broadcast(name, *args)
      self.class.broadcast(name, *arg)
    end
    private :broadcast

    #
    # 通知の送信
    #
    # @param [String] name  イベント名
    # @param [Array] args イベントで通知する引数
    #
    def notify(name, *args)
      super(name, *args) if @allow == "*" or @allow.include?(name)
    end

    #
    # 比較演算子の定義
    #
    def ===(obj)
      return (self == obj || @sock == obj)
    end

    #
    # RPC procedures
    #

		#
		# 通知要求を設定する
		#
		# @param [Array] arg
		#
		# @return [:OK] 固定値
		#
		def add_notify_request(*args)
			args.each {|type| @allow << type.to_sym}
			args.uniq!

			return :OK
		end
		remote_public :add_notify_request

		#
		# 通知要求をクリアする
		#
		# @param [Array] arg
		#
		# @return [:OK] 固定値
		#
		def clear_notify_request(*args)
			args.each {|type| @allow.delete(type.to_sym)}

			return :OK
		end
		remote_public :clear_notify_request

    #
    # 疎通確認用プロシジャー
    #
    # @return [:OK] 固定値
    #
    def hello
      return :OK
    end
    remote_public :hello

    #
    # カメラ情報の取得
    #
    # @return [:OK] カメラ情報をパックしたハッシュ
    #
    def get_camera_info
      return @app.get_camera_info()
    end
    remote_public :get_camera_info

    #
    # カメラ固有名の取得
    #
    # @return [:OK] カメラ情報をパックしたハッシュ
    #
    def get_ident_string
      return @app.get_ident_string()
    end
    remote_public :get_ident_string

    #
    # カメラの設定情報の取得
    #
    # @return [Array] カメラの設定情報の配列
    #
    def get_config
      return @app.get_config
    end
    remote_public :get_config

    #
    # 画像サイズの設定
    #
    # @param [Integer] width  新しい画像の幅
    # @param [Integer] height 新しい画像の高さ
    #
    # @return [:OK] 固定値
    #
    # @note 画像サイズの変更に伴い、update_image_sizeイベントがブロード
    #       キャストされる
    #
    def set_image_size(width, height)
      @app.set_image_size(width, height)
      return :OK
    end
    remote_public :set_image_size

    #
    # フレームレートの設定
    #
    # @param [Integer] num  新しいフレームレートの値（分子）
    # @param [Integer] deno 新しいフレームレートの値（分母）
    #
    # @return [:OK] 固定値
    #
    # @note 画像サイズの変更に伴い、update_framerateイベントがブロード
    #       キャストされる
    #
    def set_framerate(num, deno)
      @app.set_framerate(num, deno)
      return :OK
    end
    remote_public :set_framerate

    #
    # カメラの設定変更
    #
    # @param [Integer] id  設定項目のID
    # @param [Integer] val 新しい設定項目の値
    #
    # @return [:OK] 固定値
    #
    # @note 画像サイズの変更に伴い、update_controlイベントがブロード
    #       キャストされる
    #
    def set_control(num, deno)
      @app.set_control(num, deno)
      return :OK
    end
    remote_public :set_control

    #
    # 設定値の保存
    #
    # @return [:OK] 固定値
    #
    def save_config
      @app.save_config()
      return :OK
    end
    remote_public :save_config
  end
end
