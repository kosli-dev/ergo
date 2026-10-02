(function () {
  var fig = document.querySelector('[data-fromto]');
  if (!fig) return;
  var views = [].slice.call(fig.querySelectorAll('.ft__view'));
  var tabs = [].slice.call(fig.querySelectorAll('.ft__tab'));
  var steps = [].slice.call(fig.querySelectorAll('.ft__step'));
  var file = fig.querySelector('[data-file]');
  var live = fig.querySelector('.ft__views');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  fig.querySelectorAll('pre.ft__code > code').forEach(function (code) {
    code.innerHTML = code.innerHTML.split('\n').map(function (l) { return '<span class="code-line">' + l + '</span>'; }).join('\n');
  });
  var idx = 0, timer = 0, paused = false, manual = false, ticks = [];
  var clearTicks = function () { ticks.forEach(clearTimeout); ticks = []; };
  var schedule = function () {
    clearTimeout(timer);
    if (still || manual || paused || document.hidden) return;
    timer = setTimeout(function () { show(idx + 1, true); }, +views[idx].dataset.hold || 4000);
  };
  var show = function (i, animate) {
    clearTicks();
    idx = (i + views.length) % views.length;
    var v = views[idx];
    views.forEach(function (x) { x.classList.toggle('is-active', x === v); });
    tabs.forEach(function (t) { t.setAttribute('aria-pressed', t.dataset.ex === v.dataset.ex ? 'true' : 'false'); });
    steps.forEach(function (s) { s.setAttribute('aria-pressed', s.dataset.step === v.dataset.step ? 'true' : 'false'); });
    if (file) file.textContent = v.dataset.file;
    var units = [].slice.call(v.querySelectorAll('.code-line, .report__row'));
    if (!animate || still) {
      units.forEach(function (u) { u.classList.add('is-resolved'); });
    } else {
      units.forEach(function (u) { u.classList.remove('is-resolved'); });
      units.forEach(function (u, k) {
        ticks.push(setTimeout(function () { u.classList.add('is-resolved'); }, 60 + k * (u.classList.contains('report__row') ? 80 : 28)));
      });
    }
    schedule();
  };
  var jump = function (i) { manual = true; clearTimeout(timer); live.setAttribute('aria-live', 'polite'); show(i, true); };
  tabs.forEach(function (t) {
    t.addEventListener('click', function () {
      jump(views.findIndex(function (v) { return v.dataset.ex === t.dataset.ex; }));
    });
  });
  steps.forEach(function (s) {
    s.addEventListener('click', function () {
      var ex = views[idx].dataset.ex;
      jump(views.findIndex(function (v) { return v.dataset.ex === ex && v.dataset.step === s.dataset.step; }));
    });
  });
  var pause = function () { paused = true; clearTimeout(timer); };
  var resume = function () { paused = false; schedule(); };
  fig.addEventListener('mouseenter', pause);
  fig.addEventListener('mouseleave', resume);
  fig.addEventListener('focusin', pause);
  fig.addEventListener('focusout', function (e) { if (!fig.contains(e.relatedTarget)) resume(); });
  document.addEventListener('visibilitychange', function () { if (document.hidden) clearTimeout(timer); else schedule(); });
  show(0, true);
})();

(function () {
  var blocks = document.querySelectorAll('pre.code:not(.ft__code) > code');
  if (!blocks.length) return;
  var lines = function (code) {
    var parts = code.innerHTML.split('\n');
    var balanced = parts.every(function (p) {
      return (p.match(/<span\b/g) || []).length === (p.match(/<\/span>/g) || []).length;
    });
    if (!balanced) return null;
    code.innerHTML = parts.map(function (p) { return '<span class="code-line">' + p + '</span>'; }).join('\n');
    return code.querySelectorAll('.code-line');
  };
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window);
  var io = still ? null : new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      io.unobserve(entry.target);
      entry.target.querySelectorAll('.code-line').forEach(function (line, i) {
        setTimeout(function () { line.classList.add('is-resolved'); }, 150 + i * 90);
      });
    });
  }, { threshold: 0.3 });
  blocks.forEach(function (code) {
    var ls = lines(code);
    if (!ls) return;
    if (still) { ls.forEach(function (l) { l.classList.add('is-resolved'); }); return; }
    io.observe(code);
  });
})();

(function () {
  var header = document.querySelector('.site-header');
  var toggle = header && header.querySelector('.menu-toggle');
  if (!toggle) return;
  var set = function (open) {
    header.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    toggle.setAttribute('aria-label', open ? 'Close menu' : 'Menu');
  };
  toggle.addEventListener('click', function () { set(!header.classList.contains('is-open')); });
  header.querySelectorAll('.site-nav a').forEach(function (a) { a.addEventListener('click', function () { set(false); }); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && header.classList.contains('is-open')) { set(false); toggle.focus(); }
  });
  window.matchMedia('(min-width: 641px)').addEventListener('change', function (e) { if (e.matches) set(false); });
})();
