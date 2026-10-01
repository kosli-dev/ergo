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
