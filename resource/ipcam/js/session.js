/*
 * Sample for v4l2-ruby
 *
 *   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
 */

if (!msgpack || !msgpack.rpc) {
  throw "msgpack-lite.js and msgpack-rpc.js is not load yet"
}

(function () {
  Session = class extends msgpack.rpc {
    constructor(url) {
      super(url)
    }

    hello() {
      return this.remoteCall('hello');
    }

    addNotifyRequest() {
      var args;

      args = Array.prototype.slice.call(arguments);
      if (args.length == 0) {
        args = Object.keys(this.handlers);
      }

      return this.remoteCall('add_notify_request', ...args);
    }

    getCameraInfo() {
      return this.remoteCall('get_camera_info');
    }

    getIdentString() {
      return this.remoteCall('get_ident_string');
    }

    getConfig() {
      return this.remoteCall('get_config');
    }

    setImageSize(width, height) {
      return this.remoteCall('set_image_size', width, height);
    }

    setFramerate(num, deno) {
      return this.remoteCall('set_framerate', num, deno);
    }

    setControl(id, val) {
      return this.remoteCall('set_control', id, val);
    }

    saveConfig() {
      return this.remoteCall('save_config');
    }

    startCamera() {
      return this.remoteCall('start_camera');
    }

    stopCamera() {
      return this.remoteCall('stop_camera');
    }
  }
})();
