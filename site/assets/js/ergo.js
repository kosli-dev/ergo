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
