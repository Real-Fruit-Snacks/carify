// carify page: theme switch, install tabs, copy buttons, and the cluster replaying recorded runs.
// Without JS the cluster shows road-trip.mkv finished. With reduced motion nothing plays by itself,
// and picking a file shows its finished run at once.
(function () {
  var root = document.documentElement;
  var still = matchMedia('(prefers-reduced-motion: reduce)');
  var light = matchMedia('(prefers-color-scheme: light)');
  var $ = function (id) { return document.getElementById(id); };

  // ---- theme ----
  function theme() { return root.dataset.theme || (light.matches ? 'dayshift' : 'nightshift'); }
  function paint() {
    var night = theme() === 'nightshift';
    document.querySelector('meta[name="theme-color"]').content = night ? '#0C0D10' : '#F6F5F2';
    $('theme').setAttribute('aria-label', 'Theme: ' + (night ? 'night' : 'day') + '. Switch to ' + (night ? 'day' : 'night'));
  }
  $('theme').addEventListener('click', function (e) {
    var flip = function () {
      root.dataset.theme = theme() === 'nightshift' ? 'dayshift' : 'nightshift';
      try { localStorage.setItem('rfs-theme', root.dataset.theme); } catch (err) {}
      paint();
    };
    if (!document.startViewTransition || still.matches) return flip();
    var x = e.clientX || innerWidth - 40, y = e.clientY || 32;
    var r = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
    document.startViewTransition(flip).ready.then(function () {
      root.animate({ clipPath: ['circle(0 at ' + x + 'px ' + y + 'px)', 'circle(' + r + 'px at ' + x + 'px ' + y + 'px)'] },
        { duration: 520, easing: 'cubic-bezier(.2,.7,.2,1)', pseudoElement: '::view-transition-new(root)' });
    });
  });
  light.addEventListener('change', paint);
  paint();

  // ---- install tabs ----
  var tabs = [].slice.call(document.querySelectorAll('[role="tab"]'));
  function pick(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', on); t.tabIndex = on ? 0 : -1;
      $(t.getAttribute('aria-controls')).hidden = !on;
      if (on) $('copy').dataset.copy = $(t.getAttribute('aria-controls')).textContent.trim();
    });
  }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { pick(t); });
    t.addEventListener('keydown', function (e) {
      var step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (step) { var n = tabs[(i + step + tabs.length) % tabs.length]; pick(n); n.focus(); }
    });
  });
  if (/Win/.test(navigator.platform || '')) pick(tabs[1]);

  // ---- copy ----
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    var label = b.textContent;
    b.addEventListener('click', function () {
      var done = function (ok) { b.textContent = ok ? 'Copied' : 'Select it'; clearTimeout(b._t); b._t = setTimeout(function () { b.textContent = label; }, 1600); };
      if (navigator.clipboard) navigator.clipboard.writeText(b.dataset.copy).then(function () { done(true); }, function () { done(false); });
      else done(false);
    });
  });

  // ---- the cluster ----
  var data = window.CARIFY_RUNS;
  if (!data || !$('term')) return;
  var runs = {};
  data.runs.forEach(function (r) { runs[r.name] = r; });
  var dial = { v: $('dial-v'), a: $('dial-a') }, term = $('term').firstElementChild, bar = $('bar'), usb = $('usb');
  var files = [].slice.call(document.querySelectorAll('.file')), timers = [];

  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  function fmt(v) { return String(v); }
  function ang(k, v) { var d = data.dials[k]; return -data.sweep + 2 * data.sweep * Math.min(Math.max(v, 0), d.max) / d.max; }
  function needle(k, deg, s, ez) {
    var el = dial[k];
    el.style.setProperty('--t', (s == null ? 0.6 : s) + 's');
    el.style.setProperty('--ez', ez || 'cubic-bezier(.2,.7,.2,1)');
    el.style.setProperty('--a', deg.toFixed(2) + 'deg');
  }
  function hub(k, value, words, from) {
    var el = dial[k], s = value == null ? 'off' : value <= data.dials[k].limit ? 'fits' : 'over';
    var val = el.querySelector('.hub-val'), st = el.querySelector('.hub-state');
    val.textContent = value == null ? '' : fmt(value); val.dataset.s = s;
    st.textContent = value == null ? '' : s === 'fits' ? 'Fits' : 'Over'; st.dataset.s = s;
    el.querySelector('.hub-codec').textContent = words || '';
    var moved = from != null && from !== value;
    el.querySelector('.hub-from').textContent = moved ? 'from ' + fmt(from) : '';
    if (moved) { el.style.setProperty('--g', ang(k, from).toFixed(2) + 'deg'); el.setAttribute('data-ghost', ''); }
    else el.removeAttribute('data-ghost');
  }
  // The colour carify gives a status line: say() is Ember, ok() is Mint, warn() is Amber.
  function kind(line) {
    var label = line.slice(0, 6).trim(), rest = line.slice(6).trim();
    if (/^(frame|size)=/.test(line)) return 'progress';
    if (label === 'video' || label === 'audio') return rest === 'copy' ? 'ok' : 'tag';
    if (label === 'wrote' || (label === 'usb' && rest.indexOf('done') === 0)) return 'ok';
    if (label === 'warn') return 'warn';
    if (label === 'error') return 'err';
    return 'tag';
  }
  function line(text) {
    var k = kind(text);
    return k === 'progress' ? '<span class="l-progress">' + esc(text) + '</span>'
      : '<span class="l-' + k + '"><b>' + esc(text.slice(0, 6)) + '</b>' + esc(text.slice(6)) + '</span>';
  }
  function cmd(r, typed, caret) {
    return '<span class="l-cmd"><span class="ps">$</span> <span class="typed">' + esc(typed == null ? r.cmd : typed) + '</span>' + (caret ? '<span class="caret"></span>' : '') + '</span>';
  }
  function share(text, r) {
    var m = /time=(-?)(\d+):(\d+):([\d.]+)/.exec(text);
    return m && !m[1] ? Math.min((+m[2] * 3600 + +m[3] * 60 + +m[4]) / r.duration, 1) : null;
  }
  function busy(on, name) {
    files.forEach(function (f) { f.setAttribute('aria-pressed', f.dataset.run === name); });
    $('cluster').toggleAttribute('data-busy', on);
  }
  function tell(r) {
    var v = r.vin === r.vout ? r.vout + ' pixels high, copied' : r.vin + ' to ' + r.vout + ' pixels high';
    var au = r.ain === r.aout && r.awin === r.awout ? r.aout + ' channels, copied' : r.ain + ' to ' + r.aout + ' channels';
    $('cluster-say').textContent = r.file + ': video ' + v + ', ' + r.vwout + '; audio ' + au + ', ' + r.awout + '; ' + r.size + ' on the stick.';
  }
  function finish(r) {
    hub('v', r.vout, r.vwout, r.vin); hub('a', r.aout, r.awout, r.ain);
    needle('v', ang('v', r.vout), 0); needle('a', ang('a', r.aout), 0);
    term.innerHTML = [cmd(r)].concat(r.screen.map(line)).join('');
    bar.style.setProperty('--p', 1); usb.dataset.s = 'done';
    busy(false, r.name); tell(r);
  }
  function at(ms, fn) { timers.push(setTimeout(fn, ms)); }

  function play(r, ignition) {
    timers.forEach(clearTimeout); timers = [];
    busy(true, r.name);
    hub('v', null); hub('a', null);
    usb.dataset.s = 'none';
    bar.style.transition = 'none'; bar.style.setProperty('--p', 0); void bar.offsetWidth; bar.style.transition = '';
    term.innerHTML = cmd(r, '', true);
    var t0;
    if (ignition) {
      // The gauge sweep a car does when you switch it on: full scale and back, then the file's values.
      needle('v', -data.sweep, 0); needle('a', -data.sweep, 0);
      at(40, function () { needle('v', data.sweep, 0.7, 'cubic-bezier(.45,0,.55,1)'); needle('a', data.sweep, 0.7, 'cubic-bezier(.45,0,.55,1)'); });
      at(760, function () { needle('v', ang('v', r.vin), 0.7); needle('a', ang('a', r.ain), 0.7); });
      t0 = 1500;
    } else {
      needle('v', ang('v', r.vin), 0.5); needle('a', ang('a', r.ain), 0.5);
      t0 = 700;
    }
    for (var i = 1; i <= r.cmd.length; i++) (function (n) {
      at(120 + n * 26, function () { term.querySelector('.typed').textContent = r.cmd.slice(0, n); });
    })(i);
    var lines = [], redraw = false;
    r.events.forEach(function (e, i) {
      at(t0 + e[0] * 1000, function () {
        var text = e[2];
        if (i === 0) { hub('v', r.vin, r.vwin); hub('a', r.ain, r.awin); }
        if (redraw) lines[lines.length - 1] = text; else lines.push(text);
        redraw = e[1];
        term.innerHTML = [cmd(r)].concat(lines.map(line)).join('');
        var p = share(text, r);
        if (p != null) bar.style.setProperty('--p', p);
        if (/^wrote/.test(text)) {
          bar.style.setProperty('--p', 1);
          needle('v', ang('v', r.vout), 0.6); needle('a', ang('a', r.aout), 0.6);
          hub('v', r.vout, r.vwout, r.vin); hub('a', r.aout, r.awout, r.ain);
        }
        if (/^usb +copying/.test(text)) usb.dataset.s = 'copy';
        if (/^usb +done/.test(text)) usb.dataset.s = 'done';
        if (i === r.events.length - 1) {
          at(400, function () { term.insertAdjacentHTML('beforeend', '<span class="l-cmd"><span class="ps">$</span> <span class="caret"></span></span>'); busy(false, r.name); tell(r); });
        }
      });
    });
  }

  files.forEach(function (f) {
    f.addEventListener('click', function () {
      var r = runs[f.dataset.run];
      if (still.matches) finish(r); else play(r, false);
    });
  });
  if (!still.matches) play(runs['road-trip'], true);
})();
