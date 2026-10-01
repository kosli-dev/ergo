(function () {
  var blocks = document.querySelectorAll('pre.code > code');
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
  var report = document.querySelector('.report[data-evaluate]');
  if (!report) return;
  var rows = report.querySelectorAll('.report__row');
  var resolveAll = function () { rows.forEach(function (r) { r.classList.add('is-resolved'); }); };
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) {
    resolveAll();
    return;
  }
  var run = function () {
    rows.forEach(function (row, i) {
      setTimeout(function () { row.classList.add('is-resolved'); }, 420 + i * 260);
    });
  };
  var io = new IntersectionObserver(function (entries) {
    if (entries[0].isIntersecting) { io.disconnect(); run(); }
  }, { threshold: 0.3 });
  io.observe(report);
})();

(function () {
  var langs = document.querySelector('[data-langs]');
  if (!langs) return;
  var tabs = Array.prototype.slice.call(langs.querySelectorAll('[role="tab"]'));
  var select = function (tab) {
    langs.classList.add('is-live');
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute('aria-controls')).classList.toggle('is-active', on);
    });
  };
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { select(tab); });
    tab.addEventListener('keydown', function (e) {
      var step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!step) return;
      e.preventDefault();
      var next = tabs[(i + step + tabs.length) % tabs.length];
      select(next);
      next.focus();
    });
  });
  langs.classList.add('is-ready');
})();
