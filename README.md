# ipcam
Sample application for "V4L2 for Ruby".

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ipcam'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ipcam

## Usage
Connect a camera device compatible with V4L2 and start ipcam as follows.
```
ipcam [options] [device-file]
options:
        --bind=ADDR
        --port=PORT
    -d, --database-file=FILE
        --log-file=FILE
        --log-age=AGE
        --log-size=SIZE
        --log-level=LEVEL
        --develop-mode
```
Then connect to port 4567 by http browser and operate. The accessible URLs are as follows.

* http://${HOST}:4567/<br>redicrect to /main
* http://${HOST}:4567/main<br>preview and settings
* http://${HOST}:4567/stream<br>http streaming

### options
<dl>
  <dt>--bind=ADDR</dt>
  <dd>Specify the address to which the HTTP server binds. by default, IPv6 any address("::") is used.</dd>

  <dt>--port=PORT</dt>
  <dd>Specify the port number to which the HTTP server binds. by default 4567 is used.</dd>

  <dt>-d, --database-file=FILE</dt>
  <dd>Specify the file name to save the camera setting value. by default, it tries to save to "~/.ipcam.db".</dd>

  <dt>--log-file=FILE</dt>
  <dd></dd>

  <dt>--log-age=AGE</dt>
  <dd></dd>

  <dt>--log-level=LEVEL</dt>
  <dd></dd>
</dl>

### device-file
specify target device file (ex: /dev/video1). if omittedm,  it will use "/dev/video0".

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
