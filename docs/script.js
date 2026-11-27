// carify page: Cyclorama Dawn v2.1.0 theme switch (Dark LX 263 default), install tabs,
// copy buttons with semantic toasts, and the Wide-Dash 2-Bay instrument cluster.
(function () {
  var root = document.documentElement;
  var still = matchMedia('(prefers-reduced-motion: reduce)');
  var $ = function (id) { return document.getElementById(id); };

  // ---- theme (Dark LX 263 default; Light LX 512 opt-in) ----
  function currentTheme() {
    return root.dataset.theme === 'light' ? 'light' : 'dark';
  }
  function applyTheme(next) {
    if (next === 'light') {
      root.dataset.theme = 'light';
    } else {
      delete root.dataset.theme;
    }
    var isDark = currentTheme() === 'dark';
    var cs = document.querySelector('meta[name="color-scheme"]');
    if (cs) cs.content = isDark ? 'dark' : 'light';
    var tc = document.querySelector('meta[name="theme-color"]');
    if (tc) tc.content = isDark ? '#050507' : '#F5F7F9';
    var btn = $('theme');
    if (btn) {
      btn.setAttribute('aria-label', isDark ? 'Switch to Alabaster Day light mode' : 'Switch to Beacon Horizon dark mode');
    }
  }
  $('theme').addEventListener('click', function (e) {
    var next = currentTheme() === 'dark' ? 'light' : 'dark';
    var flip = function () {
      applyTheme(next);
      try {
        localStorage.setItem('rfs-theme', next);
        localStorage.setItem('color-scheme', next);
      } catch (err) {}
    };
    if (!document.startViewTransition || still.matches) return flip();
    var br = $('theme').getBoundingClientRect();
    var x = e.clientX || (br.left + br.width / 2);
    var y = e.clientY || (br.top + br.height / 2);
    var r = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
    var vt = document.startViewTransition(flip);
    var animated = vt.ready.then(function () {
      return root.animate(
        { clipPath: ['circle(0 at ' + x + 'px ' + y + 'px)', 'circle(' + r + 'px at ' + x + 'px ' + y + 'px)'] },
        { duration: 520, easing: 'cubic-bezier(.2,.7,.2,1)', pseudoElement: '::view-transition-new(root)' }
      ).finished;
    });
    Promise.allSettled([animated, vt.updateCallbackDone, vt.finished]);
  });
  window.addEventListener('storage', function (e) {
    if (e.key === 'rfs-theme' || e.key === 'color-scheme') {
      applyTheme(e.newValue === 'light' || e.newValue === 'dayshift' ? 'light' : 'dark');
    }
  });
  applyTheme(currentTheme());

  // ---- semantic toast notification ----
  var toastRegion = $('toast-region');
  var toastSr = $('toast-sr');
  function showToast(kind, tag, message) {
    if (typeof document.ariaNotify === 'function') {
      try { document.ariaNotify(message); } catch (e) {}
    } else if (toastSr) {
      toastSr.textContent = '';
      toastSr.textContent = message;
    }
    if (!toastRegion) return;
    if (typeof toastRegion.showPopover === 'function') {
      try { if (!toastRegion.matches(':popover-open')) toastRegion.showPopover(); } catch (e) {}
    }
    var item = document.createElement('div');
    item.className = 'rfs-toast is-' + kind;
    var msg = document.createElement('span');
    msg.className = 'rfs-toast-msg';
    var k = document.createElement('span');
    k.className = 'k';
    k.textContent = tag + ' ';
    msg.appendChild(k);
    msg.appendChild(document.createTextNode(message));
    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'rfs-toast-close';
    close.setAttribute('aria-label', 'Dismiss notification');
    close.textContent = '×';
    item.appendChild(msg);
    item.appendChild(close);
    toastRegion.appendChild(item);

    var remove = function () {
      if (item.parentNode) item.parentNode.removeChild(item);
      if (toastRegion.childElementCount === 0 && typeof toastRegion.hidePopover === 'function') {
        try { toastRegion.hidePopover(); } catch (e) {}
      }
    };
    close.addEventListener('click', remove);
    setTimeout(function tick() {
      if (item.contains(document.activeElement)) {
        setTimeout(tick, 1200);
        return;
      }
      remove();
    }, 2600);
  }

  // ---- install tabs ----
  var tabs = [].slice.call(document.querySelectorAll('[role="tab"]'));
  function pick(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', on);
      t.tabIndex = on ? 0 : -1;
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

  // ---- copy buttons ----
  function fallbackCopy(text) {
    try {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;';
      document.body.appendChild(ta);
      ta.select();
      var ok = document.execCommand('copy');
      ta.remove();
      return ok;
    } catch (err) {
      return false;
    }
  }
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    var label = b.textContent;
    b.addEventListener('click', function () {
      var done = function (ok) {
        b.textContent = ok ? '[ok] Copied' : 'Select text';
        showToast(ok ? 'ok' : 'warn', ok ? '[ok]' : '[!]', ok ? 'Command copied to clipboard.' : 'Copy manually from the code block.');
        clearTimeout(b._t);
        b._t = setTimeout(function () { b.textContent = label; }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(b.dataset.copy).then(function () { done(true); }, function () { done(fallbackCopy(b.dataset.copy)); });
      } else {
        done(fallbackCopy(b.dataset.copy));
      }
    });
  });

  // ---- Wide-Dash 2-Bay instrument cluster ----
  var data = window.CARIFY_RUNS;
  if (!data || !$('term')) return;
  var runs = {};
  data.runs.forEach(function (r) { runs[r.name] = r; });

  var dial = { v: $('dial-v'), a: $('dial-a') };
  var term = $('term').firstElementChild;
  var bar = $('bar');
  var usb = $('usb');
  var cmdTyped = $('cmd-typed');
  var pipeMsg = $('pipe-msg');
  var pipeTag = $('pipe-tag');
  var pipeText = $('pipe-text');
  var pipeStat = $('pipe-stat');
  var ctrl = $('cluster-ctrl');
  var files = [].slice.call(document.querySelectorAll('.file'));

  var activeRun = runs['road-trip'];
  var queue = [];
  var running = false;
  var paused = false;
  var startStamp = 0;
  var elapsedMs = 0;

  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  function fmt(v) { return String(v); }
  function ang(k, v) {
    var d = data.dials[k];
    return -data.sweep + 2 * data.sweep * Math.min(Math.max(v, 0), d.max) / d.max;
  }
  function needle(k, deg, s, ez) {
    var el = dial[k];
    el.style.setProperty('--t', (s == null ? 0.55 : s) + 's');
    el.style.setProperty('--ez', ez || 'cubic-bezier(.2,.7,.2,1)');
    el.style.setProperty('--a', deg.toFixed(2) + 'deg');
  }
  function hub(k, value, from) {
    var el = dial[k];
    var s = value == null ? 'off' : value <= data.dials[k].limit ? 'fits' : 'over';
    var val = el.querySelector('.hub-val');
    var st = el.querySelector('.hub-state');
    val.textContent = value == null ? '' : fmt(value);
    val.dataset.s = s;
    st.textContent = value == null ? '' : s === 'fits' ? 'Fits' : 'Over';
    st.dataset.s = s;
    var moved = from != null && from !== value;
    el.querySelector('.hub-from').textContent = moved ? 'from ' + fmt(from) : '';
    if (moved) {
      el.style.setProperty('--g', ang(k, from).toFixed(2) + 'deg');
      el.setAttribute('data-ghost', '');
    } else {
      el.removeAttribute('data-ghost');
    }
  }
  function setSpecs(r, ready) {
    var vAct = $('act-v'), aAct = $('act-a');
    if (vAct) {
      vAct.textContent = r.vact === 'copy' ? 'COPY' : 'RE-ENCODE';
      vAct.className = 'spec-act ' + (r.vact === 'copy' ? 'is-copy' : 'is-encode');
    }
    if (aAct) {
      aAct.textContent = r.aact === 'copy' ? 'COPY' : 'RE-ENCODE';
      aAct.className = 'spec-act ' + (r.aact === 'copy' ? 'is-copy' : 'is-encode');
    }
    $('dim-in-v').textContent = r.vdim_in;
    $('spec-in-v').textContent = r.vspec_in;
    $('dim-in-a').textContent = r.adim_in;
    $('spec-in-a').textContent = r.aspec_in;

    var outV = $('out-v'), outA = $('out-a');
    if (ready || r.vact === 'copy') {
      outV.dataset.ready = 'true';
      $('dim-out-v').textContent = r.vdim_out;
      $('spec-out-v').textContent = r.vspec_out;
    } else {
      outV.dataset.ready = 'busy';
      $('dim-out-v').textContent = 'target 720p';
      $('spec-out-v').textContent = 're-encoding h264 8-bit...';
    }
    if (ready || r.aact === 'copy') {
      outA.dataset.ready = 'true';
      $('dim-out-a').textContent = r.adim_out;
      $('spec-out-a').textContent = r.aspec_out;
    } else {
      outA.dataset.ready = 'busy';
      $('dim-out-a').textContent = 'target 2 ch';
      $('spec-out-a').textContent = 're-encoding aac 160k...';
    }
  }
  function setPipe(state, tag, text, stat) {
    pipeMsg.dataset.s = state;
    pipeTag.textContent = tag;
    pipeText.textContent = text;
    pipeStat.textContent = stat;
  }
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
    return k === 'progress'
      ? '<span class="l-progress">' + esc(text) + '</span>'
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
  function updateCtrl() {
    if (!ctrl) return;
    if (!running) ctrl.textContent = 'Replay';
    else ctrl.textContent = paused ? 'Resume' : 'Pause';
  }
  function clearQueue() {
    queue.forEach(function (item) { if (item.tid) clearTimeout(item.tid); });
    queue = [];
  }
  function scheduleAll(offset) {
    startStamp = performance.now();
    queue.forEach(function (item) {
      if (item.done) return;
      var wait = Math.max(0, item.at - offset);
      item.tid = setTimeout(function () {
        item.done = true;
        item.tid = 0;
        item.fn();
      }, wait);
    });
  }
  function finish(r) {
    clearQueue();
    running = false;
    paused = false;
    activeRun = r;
    cmdTyped.textContent = r.cmd;
    hub('v', r.vout, r.vin);
    hub('a', r.aout, r.ain);
    needle('v', ang('v', r.vout), 0);
    needle('a', ang('a', r.aout), 0);
    setSpecs(r, true);
    setPipe('ok', '[ok]', 'wrote ./' + r.out + ' (' + r.size + ') · copied to /media/runner/MOVIES', r.seconds + ' s · ' + r.speed);
    term.innerHTML = [cmd(r)].concat(r.screen.map(line)).join('');
    bar.style.setProperty('--p', 1);
    usb.dataset.s = 'done';
    busy(false, r.name);
    updateCtrl();
    tell(r);
  }
  function enqueue(ms, fn) {
    queue.push({ at: ms, fn: fn, done: false, tid: 0 });
  }
  function runSummary(r) {
    if (r.vact === 'copy' && r.aact === 'copy') return 'remuxing compliant video + audio streams to MP4...';
    if (r.vact === 'copy') return 'copying h264 video stream + re-encoding audio (aac stereo 160k)...';
    if (r.aact === 'copy') return 're-encoding video (libx264 crf 20) + copying aac audio stream...';
    return 're-encoding video (libx264 crf 20) + audio (aac stereo 160k)...';
  }

  function play(r) {
    clearQueue();
    activeRun = r;
    running = true;
    paused = false;
    elapsedMs = 0;
    busy(true, r.name);
    updateCtrl();

    cmdTyped.textContent = '';
    hub('v', r.vin);
    hub('a', r.ain);
    needle('v', ang('v', r.vin), 0.5);
    needle('a', ang('a', r.ain), 0.5);
    setSpecs(r, false);
    setPipe('run', '[run]', runSummary(r), 'encoding...');
    usb.dataset.s = 'none';
    bar.style.transition = 'none';
    bar.style.setProperty('--p', 0);
    void bar.offsetWidth;
    bar.style.transition = '';
    term.innerHTML = cmd(r, '', true);

    var t0 = 580;
    for (var i = 1; i <= r.cmd.length; i++) (function (n) {
      enqueue(60 + n * 22, function () {
        var partial = r.cmd.slice(0, n);
        cmdTyped.textContent = partial;
        var typedEl = term.querySelector('.typed');
        if (typedEl) typedEl.textContent = partial;
      });
    })(i);

    var lines = [], redraw = false;
    r.events.forEach(function (e, idx) {
      enqueue(t0 + e[0] * 1000, function () {
        var text = e[2];
        if (redraw) lines[lines.length - 1] = text;
        else lines.push(text);
        redraw = e[1];
        term.innerHTML = [cmd(r)].concat(lines.map(line)).join('');
        var p = share(text, r);
        if (p != null) bar.style.setProperty('--p', p);
        if (/^wrote/.test(text)) {
          bar.style.setProperty('--p', 1);
          needle('v', ang('v', r.vout), 0.55);
          needle('a', ang('a', r.aout), 0.55);
          hub('v', r.vout, r.vin);
          hub('a', r.aout, r.ain);
          setSpecs(r, true);
          setPipe('ok', '[ok]', 'wrote ./' + r.out + ' (' + r.size + ') · copied to /media/runner/MOVIES', r.seconds + ' s · ' + r.speed);
        }
        if (/^usb +copying/.test(text)) usb.dataset.s = 'copy';
        if (/^usb +done/.test(text)) usb.dataset.s = 'done';
      });
    });
    var endMs = t0 + (r.events.length ? r.events[r.events.length - 1][0] * 1000 : 0) + 350;
    enqueue(endMs, function () {
      term.insertAdjacentHTML('beforeend', '<span class="l-cmd"><span class="ps">$</span> <span class="caret"></span></span>');
      running = false;
      paused = false;
      busy(false, r.name);
      updateCtrl();
      tell(r);
    });
    scheduleAll(0);
  }

  if (ctrl) {
    ctrl.addEventListener('click', function () {
      if (!running) {
        if (still.matches) finish(activeRun);
        else play(activeRun);
        return;
      }
      if (!paused) {
        paused = true;
        elapsedMs += performance.now() - startStamp;
        queue.forEach(function (item) { if (item.tid) { clearTimeout(item.tid); item.tid = 0; } });
        updateCtrl();
      } else {
        paused = false;
        updateCtrl();
        scheduleAll(elapsedMs);
      }
    });
  }

  files.forEach(function (f) {
    f.addEventListener('click', function () {
      var r = runs[f.dataset.run];
      if (still.matches) finish(r);
      else play(r);
    });
  });

  if (still.matches) finish(runs['road-trip']);
  else play(runs['road-trip']);
})();
