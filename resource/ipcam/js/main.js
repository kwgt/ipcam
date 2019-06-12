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
  var sliders;

  var imageWidth;
  var imageHeight;
  var framerate;

  var previewCanvas;
  var previewGc;

  /*
   * declar functions
   */

  function setDeviceFile(name) {
    $('h3#device-file').text(name);
  }

  function setState(state) {
    var fg;
    var bg;
    var lb;

    switch (state) {
      case "STOP":
      default:
        fg = "royalblue";
        bg = "white";
        lb = "START";
        break;

      case "ALIVE":
        fg = "springgreen";
        bg = "black";
        lb = "STOP";
        break;

      case "ABORT":
        fg = "crimson";
        bg = "white";
        lb = "RECOVER";
        break;
    }

    $('button#action').text(lb);

    $('div#state')
      .css('color', fg)
      .css('-webkit-text-stroke', `0.5px ${bg}`)
      .text(state);
  }

  function setupScreenSize() {
    var height;

    height = $('body').height() - $('div.jumbotron').outerHeight(true);
    $('div#main-area').height(height);

    $('div#preview').getNiceScroll().resize();
    $('div#config').getNiceScroll().resize();
  }

  function setIdentString(str) {
    $('h6#device-name').text(str);
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

  function findCapability() {
    var ret;

    ret = capabilities.find((obj) => {
      return ((obj.width == imageWidth) && (obj.height == imageHeight));
    });

    return ret;
  }

  function selectFramerate(rates) {
    var list;
    var targ;

    targ = framerate[0] / framerate[1];

    if (!rates) {
      rates = findCapability()["rate"];
    }

    list = rates.concat();

    list.sort((a, b) => {
      return  Math.abs((a[0] / a[1]) - targ) - Math.abs((b[0] / b[1]) - targ);
    });

    $('select#framerate').val(`${list[0][0]},${list[0][1]}`);
  }

  function setFramerateSelect() {
    var info;

    $('select#framerate')
      .empty()
      .off('change');

    info = findCapability();

    if (info) {
      info["rate"].forEach((obj) => {
        $('select#framerate')
          .append($('<option>')
            .attr('value', `${obj[0]},${obj[1]}`)
            .text(framerateString(obj))
          );
      });

      selectFramerate(info['rate']);

      $('select#framerate')
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
      .attr('type', 'range');

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
    
    sliders[info["id"]] = $input
      .ionRangeSlider({
        type:               "single",
        min:                info["min"],
        max:                info["max"],
        step:               info["step"],     
        from:               info["value"],
        skin:               "sharp",
        keyboard:           true,
        hide_min_max:       true,
        grid:               true,
        grid_num:           (tics > 10)? 10: tics,
        prettify_separator: ",",

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
        .addClass('form-group')
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

    sliders = {};

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

  function updateImage(data) {
    Utils.loadImageFromData(data)
      .then((img) => {
        updatePreviewCanvas(img);
      })
      .fail((error) => {
        console.log(error);
      });
  }

  function updateImageSize(width, height) {
    imageWidth  = width;
    imageHeight = height;

    resizePreviewCanvas();
    setFramerateSelect();
  }

  function updateFramerate(num, deno) {
    framerate = [num, deno]
    selectFramerate();
  }

  function updateControl(id, val) {
    var info;

    info = controls.find((obj) => obj["id"] == id);

    switch (info["type"]) {
    case "boolean":
      $(`input#control-${id}`).prop('checked', val);
      break;

    case "integer":
      $(`input#control-${id}`).data('ionRangeSlider').update({from:val});
      break;

    case "menu":
      $(`select#control-${id}`).val(val);
      break;
    }

  }

  function changeState(state) {
    var pr1;
    var pr2;

    setState(state);

    if (state == "ALIVE") {
      pr1 = session.getIdentString()
        .then((str) => {
          setIdentString(str);
        });

      pr2 = session.getConfig()
        .then((info) => {
          let rates;

          capabilities = info["capabilities"];
          controls     = info["controls"];
          imageWidth   = info["image_width"];
          imageHeight  = info["image_height"];
          framerate    = info["framerate"];

          resizePreviewCanvas();
          sortCapabilities();
          setImageSizeSelect();
          setFramerateSelect();

          setControlForm(info["controls"]);

          $('div#config').getNiceScroll().resize();
        });

      $.when(pr1, pr2)
        .done(() => {
          setupScreenSize();
        });

    } else {
      $('h6#device-name').text(null);

      $('select#image-size > option').remove();
      $('select#framerate > option').remove();
      $('div#controls').empty();

      $('div#config').getNiceScroll().resize();

      setupScreenSize();
    }
  }

  function startSession() {
    session
      .on('update_image', (data) => {
        updateImage(data);
      })
      .on('update_image_size', (width, height) => {
        updateImageSize(width, height);
      })
      .on('update_framerate', (num, deno) => {
        updateFramerate(num, deno);
      })
      .on('update_control', (id, val) => {
        updateControl(id, val);
      })
      .on('change_state', (state) => {
        changeState(state);
      })
      .on('save_complete', () => {
        console.log("come");
        $('#save-complete-toast').toast('show');
      });

    session.start()
      .then(() => {
        return session.getCameraInfo();
      })
      .then((info) => {
        setDeviceFile(info["device"]);
        changeState(info["state"]);

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
        $('#url-copied-toast').toast('show');
      });
  }

  function initialize() {
    session       = new Session(WS_URL);
    capabilities  = null;
    controls      = null;
    sliders       = null;
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

  $(window)
  .on('resize', () => {
    setupScreenSize();
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
