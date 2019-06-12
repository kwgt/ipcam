/*
 * 雑多な処理を集めたコード
 *
 *  (C) 2017 Hiroshi Kuwagata <kgt9221@gmail.com>
 */

(function () {
  function readJavaScript(src) {
    return $.getScript(src);
  }

  function readCss(src) {
    var $df;

    $df = new $.Deferred();

    $('head')
      .append($('<link>')
        .on('load', () => {
          $df.resolve();
        })
        .attr("rel", "stylesheet")
        .attr("type", "text/css")
        .attr("href", src)
      );

    return $df.promise();
  }

  function getResource(list, $df) {
    var src;

    src = list.shift();

    if (/\.js$/.test(src)) {
      readJavaScript(src)
        .then((script, state) => {
          getResource(list, $df);
        })
        .fail((error) => {
          $df.reject(error);
        });

    } else if (/\.(css|scss)$/.test(src)) {
      readCss(src)
        .then(() => {
          getResource(list, $df);
        })
        .fail((error) => {
          $df.reject(error);
        });

    } else if (src == null) {
      $df.resolve();
    }
  }

  function loadImage(url, dst) {
    var $df;

    $df = new $.Deferred();

    if (!dst) {
      dst = new Image();
    } else {
      if (dst instanceof jQuery) {
        dst = dst[0];
      }

      if (!(dst instanceof Image)) {
        throw("not image object");
      }
    }

    $(dst)
      .on('load', () => {
        $df.resolve(dst);
      })
      .on('error', (e) => {
        $df.reject(e);
      })
      .attr('src', url);

    return $df.promise();
  }

  Utils = class {
    static require(list) {
      var $df;

      $df = new $.Deferred()

      getResource(list, $df);

      return $df.promise();
    }

    static loadImageFromData(data) {
      var $df;
      var blob;
      var url;

      $df  = new $.Deferred();
      blob = new Blob([data.data], {type: data.type});
      url  = URL.createObjectURL(blob);

      loadImage(url)
        .then((img) => {
          $df.resolve(img);
        })
        .fail((error) => {
          $df.reject(error);
        })
        .always(() => {
          URL.revokeObjectURL(url);
        });

      return $df.promise();
    }

    static copyToClipboard(text) {
      var $text;

      $text = $('<textarea>').css('visible', 'hidden');
      $('body').append($text);

      $text
        .val(text)
        .select();
      document.execCommand('copy');

      $text.remove();
    }

    static showAbortShield(html) {
      $('body').css('overflow', 'hidden');

      $('#abort-shield')
        .find('p')
          .html(html)
        .end()
        .fadeIn();
    }
  }
})();
