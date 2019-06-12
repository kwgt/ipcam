/*
 * MessagePack RPC base class
 *
 *  (C) 2017 Hiroshi Kuwagata <kgt9221@gmail.com>
 */

if (!msgpack) {
  throw "msgpack-lite is not load yet"
}

(function () {
  /* declar local symbol */
  const newId       = Symbol('newId');
  const callback    = Symbol('callback');
  const recv        = Symbol('recv');

  /* declar contant */
  const DEFAULT_URL = `ws://${location.hostname}:${parseInt(location.port)+1}/`;
  const COEDEC      = msgpack.createCodec({binarraybuffer:true, preset:true});
  const ENC_OPT     = {codec:COEDEC};

  msgpack.rpc = class {
    /*
     * core functions
     */
    constructor (url) {
      this.url      = url || DEFAULT_URL
      this.sock     = null;
      this.deferred = null;
      this.maxId    = 1;
      this.handlers = {}
    }

    [newId]() {
      return this.maxId++;
    }

    [callback](name, args) {
      if (this.handlers[name]) {
        this.handlers[name](...args);
      } else {
        throw `unhandled notification received (${name}).`;
      }
    }

    [recv](data) {
      var self;
      var msg;
      var type;
      var id;
      var meth;
      var err;
      var res;
      var para;
      var $df;

      msg  = msgpack.decode(new Uint8Array(data), ENC_OPT);
      type = msg[0];

      switch (type) {
      case 1:
        id  = msg[1];
        err = msg[2];
        res = msg[3];
        $df = this.deferred[id];

        if ($df) {
          if (err) {
            $df.reject(err);
          } else {
            $df.resolve(res);
          }
        }

        delete this.deferred[id];
        break;

      case 2:
        meth = msg[1];
        para = msg[2];

        if (!para) {
          para = [];
        } else if (!(para instanceof Array)) {
          para = [para];
        }

        this[callback](meth, para);
        break;

      default:
        throw `Illeagal data (type=${type}) recevied.`;
      }
    }

    remoteCall(meth) {
      var id;
      var $df;
      var args;

      id   = this[newId]();
      $df  = new $.Deferred();
      args = Array.prototype.slice.call(arguments, 1);

      switch (args.length) {
      case 0:
        args = null;
        break;

      case 1:
        args = args[0];
        break;
      }

      this.deferred[id] = $df;
      this.sock.send(msgpack.encode([0, id, meth, args], ENC_OPT));

      return $df.promise();
    }

    remoteNotify(meth) {
      var args;

      args = Array.prototype.slice.call(arguments, 1);

      switch (args.length) {
      case 0:
        args = null;
        break;

      case 1:
        args = args[0];
        break;
      }

      this.sock.send(msgpack.encode([2, meth, args], ENC_OPT));
    }

    on(name, func) {
      this.handlers[name] = func;
      return this;
    }

    start() {
      var $df;

      $df = new $.Deferred();

      if (!this.sock) {
        this.sock = new WebSocket(this.url);

        this.sock.binaryType = "arraybuffer";

        this.sock.onopen = () => {
          this.deferred = {}
          $df.resolve();
        };

        this.sock.onerror = () => {
          $df.reject();
        };

        this.sock.onmessage = (m) => {
          this[recv](m.data);
        };

        this.sock.onclose = () => {
          this[callback]('session_closed', []);
          this.sock = null;
        };
      }

      return $df.promise();
    }

    finish() {
      var id;

      this.sock.close();

      for (id in this.deferred) {
        this.deferred[id].reject("session finished");
        delete this.deferred[id];
      }

      this.sock     = null;
      this.deferred = null;
    }
  }
})();

