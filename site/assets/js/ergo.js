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
