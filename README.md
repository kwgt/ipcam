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
        --use-ssl
        --ssl-cert=CRT-FILE
        --ssl-key=KEY-FILE
    -D, --digest-auth=FILE
    -A, --add-user=USER,PASSWD
        --bind=ADDR
        --port=PORT
    -d, --database-file=FILE
    -e, --extend-header
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
  <dt>--use-ssl</dt>
  <dd>Specify use SSL/TLS. If you use this option, shall specify a certificate file and a key file (Use the --ssl-cert and --ssl-key options).</dd>

  <dt>--ssl-cert=CRT-FILE</dt>
  <dd>Specifies the file that contains the X 509 server certificate.</dd>

  <dt>--ssl-key=KEY-FILE</dt>
  <dd>Specifies the key file that was used when the certificate was created.</dd>

  <dt>-D, --digest-auth=YAML-FILE</dt>
  <dd>Specifies to use restrict access by Digest Authentication. This argument is followed by a password file written in YAML.</dd>

  <dt>-A, --add-user=USER-NAME,PASSWORD</dt>
  <dd>Add entry to the password file. If you specify this option, only to add an entry to the password file to exit this application.</dd>

  <dt>--bind=ADDR</dt>
  <dd>Specify the address to which the HTTP server binds. by default, IPv6 any address("::") is used.</dd>

  <dt>--port=PORT</dt>
  <dd>Specify the port number to which the HTTP server binds. by default 4567 is used.</dd>

  <dt>-d, --database-file=FILE</dt>
  <dd>Specify the file name to save the camera setting value. by default, it tries to save to "~/.ipcam.db".</dd>

  <dt>-e, --extend-header</dt>
  <dd>Add extend header to part data (for debug).</dd>

  <dt>--log-file=FILE</dt>
  <dd></dd>

  <dt>--log-age=AGE</dt>
  <dd></dd>

  <dt>--log-level=LEVEL</dt>
  <dd></dd>
</dl>

### Use digest authentication
To restrict access by digest authentication, the password file written in YAML must be specified in the "--digest-auth" option. This file must be YAML-encoded map data of A1 strings (ref. RFC 7616) keyed by the user name.

This file can be created using the "--add-user" option. The actual procedure is as follows. 

#### Create password file
##### create password file, and add user "foo"
If specified password file does not exist and the "--digest-auth" and "--add-user" options are specified together, new password file containing user entry will be created.
```
ipcam --digest-auth passwd.yml --add-user foo,XXXXXXX
```

##### and add user "bar"
If specified password file exists and the "--digest-auth" option and "--add-user" option are specified together, a user entry is added to the password file.
```
ipcam --digest-auth passwd.yml --add-user bar,YYYYYY
```

#### Run the server
If only the "--digest-auth" option is specified, the server is started and performs digest authentication with the specified password file.
```
ipcam --digest-auth passwd.yml --use-ssl --ssl-cert cert/server.crt --ssl-key cert/server.key /dev/video0
```

#### Delete user from password file
To delete a user, edit the YAML file directly.

### device-file
specify target device file (ex: /dev/video1). if omittedm,  it will use "/dev/video0".

## etc
### About image data
いらすとや (https://www.irasutoya.com) で配布されている『特撮映画のイラスト』(https://www.irasutoya.com/2018/12/blog-post_90.html) を改変して使用しています。

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
