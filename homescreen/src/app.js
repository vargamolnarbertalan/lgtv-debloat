// Minimal webOS home screen: a clock and your installed apps, nothing else.
// Written for this TV's Chromium 53: no async/await, no arrow functions
// assumed critical, ES5 throughout -- same constraint as the sister Flex
// Plex client this project borrows its toolchain/packaging approach from.
(function () {
  'use strict';

  // Dev-only diagnostic channel, same pattern as the Flex client's devlog --
  // a fire-and-forget beacon to a throwaway local HTTP listener on the dev
  // PC, since there's no way to screenshot the TV during development.
  // Harmless if the listener isn't running. Remove before any real-world use.
  var DEVLOG_URL = 'http://PASTE_DEVLOG_HOST:8791/log'; // your dev machine's LAN IP, for testing only
  function devlog(event, data) {
    try {
      var qs = new URLSearchParams();
      qs.set('app', 'homescreen');
      qs.set('event', event);
      Object.keys(data || {}).forEach(function (k) {
        var v = data[k];
        qs.set(k, v === null || v === undefined ? '' : String(v));
      });
      fetch(DEVLOG_URL + '?' + qs.toString()).catch(function () {});
    } catch (e) { /* devlog must never break the app */ }
  }

  var clockEl = document.getElementById('clock');
  var dateEl = document.getElementById('date');
  var statusEl = document.getElementById('status');
  var gridEl = document.getElementById('appgrid');

  var GRID_COLUMNS = 8; // only used for Up/Down index math -- the actual
    // layout is a CSS flex-wrap, so this doesn't need to match the real
    // rendered column count exactly, just be a reasonable approximation
    // (same tolerant approach the Flex client's grid nav uses).

  var apps = [];
  var focusedIndex = 0;

  function pad2(n) { return n < 10 ? '0' + n : String(n); }

  function updateClock() {
    var now = new Date();
    clockEl.textContent = pad2(now.getHours()) + ':' + pad2(now.getMinutes());
    var days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    var months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    dateEl.textContent = days[now.getDay()] + ', ' + months[now.getMonth()] + ' ' + now.getDate();
  }

  function setStatus(text) {
    statusEl.textContent = text || '';
  }

  function focusTile(index) {
    var tiles = gridEl.children;
    if (!tiles.length) return;
    if (index < 0) index = 0;
    if (index >= tiles.length) index = tiles.length - 1;
    for (var i = 0; i < tiles.length; i++) tiles[i].classList.remove('focused');
    focusedIndex = index;
    tiles[focusedIndex].classList.add('focused');
  }

  // listLaunchPoints is denied "category /" on the PUBLIC Luna bus
  // (luna-send-pub) no matter who calls it -- confirmed directly over
  // telnet as root, so it's not an app-sandbox/ACG problem at all (declaring
  // application.operation/application.launcher in requiredACG made no
  // difference, matching an unresolved LG forum report of the same error).
  // luna-send (PRIVATE bus, no -pub) returns the real list fine, even from
  // the exact same root shell. A sideloaded web app has no private-bus
  // access of its own, so this goes through Homebrew Channel's own
  // root-exec relay instead -- it runs the command as a real root shell on
  // the device, same as this project's own deploy.py does over telnet, just
  // triggered from inside the app.
  function hbExec(command, onSuccess, onFailure) {
    window.webOS.service.request('luna://org.webosbrew.hbchannel.service', {
      method: 'exec',
      parameters: { command: command },
      onSuccess: onSuccess,
      onFailure: onFailure
    });
  }

  function launchApp(app) {
    devlog('app:launch', { id: app.id, title: app.title });
    setStatus('Launching ' + app.title + '...');
    var cmd = "luna-send-pub -n 1 luna://com.webos.applicationManager/launch '"
      + JSON.stringify({ id: app.id, params: app.params || {} }) + "'";
    hbExec(cmd, function (res) {
      devlog('app:launch:ok', { id: app.id, stdout: res && res.stdoutString });
      setStatus('');
    }, function (res) {
      devlog('app:launch:failed', { id: app.id, errorCode: res && res.errorCode, errorText: res && res.errorText });
      setStatus('Could not launch ' + app.title);
    });
  }

  // Icons live as plain files elsewhere on the filesystem (other apps'
  // install directories) -- neither a bare absolute path nor an explicit
  // file:// URI loads in an <img> here, confirmed on real hardware (WAM
  // sandboxes a web app's resource loading to its own bundle, no exception
  // for other apps' public icon assets). Reading the bytes through the same
  // hbExec root-shell relay already used for listLaunchPoints/launch and
  // handing them back as a data: URI sidesteps the browser's own resource
  // loader entirely, so WAM's restriction never applies.
  function loadIconDataUri(path, onDone) {
    hbExec("cat '" + path + "' | base64", function (res) {
      var b64 = (res.stdoutString || '').replace(/\s+/g, '');
      onDone(b64 ? 'data:image/png;base64,' + b64 : null);
    }, function () { onDone(null); });
  }

  function renderGrid() {
    gridEl.innerHTML = '';
    apps.forEach(function (app) {
      var tile = document.createElement('div');
      tile.className = 'app-tile';

      var icon = document.createElement('img');
      icon.className = 'app-tile__icon';
      icon.alt = app.title;
      tile.appendChild(icon);
      if (app.icon) {
        loadIconDataUri(app.icon, function (dataUri) {
          if (dataUri) icon.src = dataUri;
          else devlog('icon:load-failed', { id: app.id, src: app.icon });
        });
      }

      var label = document.createElement('div');
      label.className = 'app-tile__label';
      label.textContent = app.title;
      tile.appendChild(label);

      tile.addEventListener('click', function () { launchApp(app); });
      gridEl.appendChild(tile);
    });
    focusTile(0);
  }

  function loadApps() {
    setStatus('Loading apps...');
    devlog('apps:list:start');
    hbExec("luna-send -n 1 luna://com.webos.applicationManager/listLaunchPoints '{}'", function (res) {
      var data;
      try {
        data = JSON.parse(res.stdoutString);
      } catch (e) {
        devlog('apps:list:parse-failed', { message: e.message, stdoutString: (res.stdoutString || '').slice(0, 200) });
        setStatus('Could not parse app list');
        return;
      }
      var points = data.launchPoints || [];
      apps = points.map(function (p) {
        return { id: p.id, title: p.title || p.id, icon: p.icon, params: p.params };
      });
      devlog('apps:list:ok', { count: apps.length });
      setStatus('');
      renderGrid();
    }, function (res) {
      devlog('apps:list:failed', { errorCode: res && res.errorCode, errorText: res && res.errorText });
      setStatus('Could not load installed apps (' + ((res && res.errorText) || 'unknown error') + ')');
    });
  }

  document.addEventListener('keydown', function (e) {
    var tiles = gridEl.children;
    if (!tiles.length) return;
    if (e.key === 'ArrowRight') { focusTile(focusedIndex + 1); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { focusTile(focusedIndex - 1); e.preventDefault(); }
    else if (e.key === 'ArrowDown') { focusTile(focusedIndex + GRID_COLUMNS); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { focusTile(focusedIndex - GRID_COLUMNS); e.preventDefault(); }
    else if (e.key === 'Enter') { launchApp(apps[focusedIndex]); e.preventDefault(); }
  });

  devlog('app:boot', { hasWebOS: !!(window.webOS && window.webOS.service) });
  updateClock();
  setInterval(updateClock, 1000);
  loadApps();
})();
