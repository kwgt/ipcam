/*
 * Sample for v4l2-ruby
 *
 *   Copyright (C) 2019 Hiroshi Kuwagata <kgt9221@gmail.com>
 */

(function () {
  /*
   * define constants
   */

  const WS_URL = `ws://${location.hostname}:${parseInt(location.port)+1}/`;

  /*
   * declar package global variabled
   */

  var session;
  var capabilities;
  var controls;

  var imageWidth;
  var imageHeight;
  var framerate;

  var previewCanvas;
  var previewGc;

  /*
   * declar functions
   */

  function setCameraInfo(info) {
    var fg;
    var bg;

    $('h3#device-file').text(info["device"]);

    switch (info["state"]) {
      case "READY":
      default:
        fg = "royalblue";
        bg = "white";
        break;

      case "BUSY":
        fg = "gold";
        bg = "black";
        break;

      case "ABORT":
        fg = "crimson";
        bg = "white";
    }

    $('div#state')
      .css('color', fg)
      .css('-webkit-text-stroke', `0.5px ${bg}`)
      .text(info["state"]);
  }

  function setIdentString(str) {
    var height;

    $('h5#device-name').text(str);

    height = $('body').height() - $('div.jumbotron').outerHeight(true);
    $('div#main-area').height(height);
  }

  function sortCapabilities() {
    capabilities.sort((a, b) => {
      return ((a.width * a.height) - (b.width * b.height));
    });

    capabilities.forEach((info) => {
      info["rate"].sort((a, b) => {return (a[0] / a[1]) - (b[0] / b[1])});
    });
  }

  function setImageSizeSelect() {
    /*
     * 画像サイズ
     */
    $('select#image-size').empty();

    capabilities.forEach((obj) => {
      $('select#image-size')
        .append($('<option>')
          .attr('value', `${obj.width},${obj.height}`)
          .text(`${obj.width} \u00d7 ${obj.height}`)
        );
    });

    $('select#image-size')
      .val(`${imageWidth},${imageHeight}`)
      .on('change', (e) => {
        let val;
        let res;

        val = $(e.target).val();
        res = val.match(/(\d+),(\d+)/);

        session.setImageSize(parseInt(res[1]), parseInt(res[2]));
      });
  }

  function framerateString(val) {
    var ret;

    ret = Math.trunc((val[0] / val[1]) * 100) / 100;

    return `${ret} fps`;
  }

  function chooseFramerate(rate) {
    var info;
    var list;
    var targ;

    targ = rate[0] / rate[1];

    info = capabilities.find((obj) => {
      return ((obj.width == imageWidth) && (obj.height == imageHeight));
    });

    list = info["rate"].reduce((m, n) => {m.push(n); return m}, []);
    list.sort((a, b) => {
      return  Math.abs((a[0] / a[1]) - targ) - Math.abs((b[0] / b[1]) - targ);
    });

    return `${list[0][0]},${list[0][1]}`;
  }

  function setFramerateSelect() {
    var info;

    /*
     * フレームレート
     */

    $('select#framerate').empty();

    info = capabilities.find((obj) => {
      return ((obj.width == imageWidth) && (obj.height == imageHeight));
    });

    if (info) {
      info["rate"].forEach((obj) => {
        $('select#framerate')
          .append($('<option>')
            .attr('value', `${obj[0]},${obj[1]}`)
            .text(framerateString(obj))
          );
      });

      $('select#framerate')
        .val(chooseFramerate(framerate))
        .on('change', (e) => {;
          let val;
          let res;

          val = $(e.target).val();
          res = val.match(/(\d+),(\d+)/)

          session.setFramerate(parseInt(res[1]), parseInt(res[2]));
        });
    }
  }

  function addIntegerForm(info) {
    var $input;
    var tics;

    $input = $('<input>')
      .attr('id', `control-${info["id"]}`)
      .attr('type', 'range')
      .attr('value', info["value"]);

    $('div#controls')
      .append($('<div>')
        .addClass("mb-2")
        .append($('<label>')
          .addClass("form-label")
          .attr("for", `control-${info["id"]}`)
          .text(info["name"])
        )
        .append($('<div>')
          .addClass('form-group ml-3')
          .append($input)
        )
      );

    tics = info["max"] - info["min"];
    
    $input
      .ionRangeSlider({
        type:         "single",
        min:          info["min"],
        max:          info["max"],
        step:         info["step"],     
        skin:         "sharp",
        keyboard:     true,
        hide_min_max: true,
        grid:         true,
        grid_num:     (tics > 10)? 10: tics,

        onFinish: (data) => {
          session.setControl(info["id"], data["from"])
        }
      });
  }

  function addBooleanForm(info) {
    var $input;

    $input = $('<input>')
      .attr('id', `control-${info["id"]}`)
      .attr('type', 'checkbox')
      .attr('checked', info["value"])
      .on('change', (e) => {
        session.setControl(info["id"], $(e.target).is(':checked'));
      });

    $('div#controls')
      .append($('<div>')
        .addClass('pretty p-default my-2')
        .append($input)
        .append($('<div>')
          .addClass('state p-primary')
          .append($('<label>')
            .addClass('form-label')
            .attr("for", `control-${info["id"]}`)
            .text(info["name"])
          )
        )
      );
  }

  function addMenuForm(info) {
    var $select;

    $select = $('<select>')
      .attr('id', `control-${info["id"]}`)
      .addClass('form-control offset-1 col-11');

    for (const [label, value] of Object.entries(info["items"])) {
      $select
        .append($('<option>')
          .attr("value", value)
          .text(label)
        );
    }

    $select
      .val(info["value"])
      .on('change', (e) => {
        session.setControl(info["id"], parseInt($(e.target).val()));
      });

    $('div#controls')
      .append($('<div>')
        .addClass("form-group")
        .append($('<label>')
          .addClass('form-label')
          .attr("for", `control-${info["id"]}`)
          .text(info["name"])
        )
        .append($select)
      );
  }

  function setControlForm(info) {
    $('div#controls').empty();

    $('div#controls').append($("<hr>"));

    info.forEach((entry) => {
      if (entry["type"] == "boolean") {
        addBooleanForm(entry);
      }
    });

    $('div#controls').append($("<hr>"));

    info.forEach((entry) => {
      if (entry["type"] == "menu") {
        addMenuForm(entry);
      }
    });

    $('div#controls').append($("<hr>"));

    info.forEach((entry) => {
      if (entry["type"] == "integer") {
        addIntegerForm(entry);
      }
    });
  }

  function resizePreviewCanvas() {
    previewCanvas.width  = imageWidth;
    previewCanvas.height = imageHeight;

    $('div#preview').getNiceScroll().resize();
  }

  function updatePreviewCanvas(img) {
    previewGc.drawImage(img,
                        0,
                        0,
                        img.width,
                        img.height,
                        0,
                        0,
                        imageWidth,
                        imageHeight);
  }

  function startSession() {
    session
      .on('update_image', (data) => {
        Utils.loadImageFromData(data)
          .then((img) => {
            updatePreviewCanvas(img);
          })
          .fail((error) => {
            console.log(error);
          });
      })
      .on('update_image_size', (width, height) => {
        imageWidth  = width;
        imageHeight = height;

        resizePreviewCanvas();
        setFramerateSelect();
      })
      .on('update_framerate', (num, deno) => {
        console.log("not implemented yet");
      })
      .on('update_control', (id, val) => {
        console.log("not implemented yet");
      });

    session.start()
      .then(() => {
        return session.getCameraInfo();
      })
      .then((info) => {
        setCameraInfo(info);

        if (info["state"] == "BUSY") {
          session.getIdentString()
            .then((str) => {
              setIdentString(str);
            });

          session.getConfig()
            .then((info) => {
              let rates;

              capabilities = info["capabilities"];
              controls     = info["controls"];
              imageWidth   = info["image_width"];
              imageHeight  = info["image_height"];
              framerate    = info["framerate"];

              sortCapabilities();

              resizePreviewCanvas();
              setImageSizeSelect();
              setFramerateSelect();

              setControlForm(info["controls"]);

              $('div#config').getNiceScroll().resize();
            });
        }

        return session.addNotifyRequest();
      })
      .fail((error) => {
        console.log(error);
      });
  }

  function setupScreen() {
    $('div#preview')
      .niceScroll({
        enablekeyboard:   true,
        zindex:           100,
        autohidemode:     true,
        horizrailenabled: false
      });

    $('div#config')
      .niceScroll({
        enablekeyboard:   true,
        zindex:           100,
        autohidemode:     true,
        horizrailenabled: false
      });
  }

  function setupButtons() {
    $('button#save-config')
      .on('click', () => {
        session.saveConfig();
      });

    $('button#copy-url')
      .on('click', () => {
        let url;

        url = `${location.protocol}//${location.host}/stream`;
        Utils.copyToClipboard(url);
      });
  }

  function initialize() {
    session       = new Session(WS_URL);
    capabilities  = null;
    controls      = null;
    imageWidth    = null;
    imageHeight   = null;
    framerate     = null;
    previewCanvas = $('canvas#preview-canvas')[0];
    previewGc     = previewCanvas.getContext('2d');

    setupScreen();
    setupButtons();

    startSession();
  }

  /*
   * set handler for global objects
   */

  /* エントリーポイントの設定 */
  $(window)
  .on('load', () => {
    let list = [
      "/css/bootstrap.min.css",
      "/css/ion.rangeSlider.min.css",
      "/css/pretty-checkbox.min.css",

      "/js/popper.min.js",
      "/js/bootstrap.min.js",
      "/js/msgpack.min.js",
      "/js/jquery.nicescroll.min.js",
      "/js/ion.rangeSlider.min.js",

      "/css/main/style.scss",
      "/js/msgpack-rpc.js",
      "/js/session.js",
    ];

    Utils.require(list)
      .done(() => {
        initialize();
      });
  });

  /* デフォルトではコンテキストメニューをOFF */
  $(document)
    .on('contextmenu', (e) => {
      e.stopPropagation();
      return false;
    });

  /* Drop&Dragを無効にしておく */
  $(document)
    .on('dragover', (e) => {
      e.stopPropagation();
      return false;
    })
    .on('dragenter', (e) => {
      e.stopPropagation();
      return false;
    })
    .on('drop', (e) => {
      e.stopPropagation();
      return false;
    });
})();
