/* ── MaterialDocs: Theme Toggle ──
   Dark mode toggle with system preference detection and localStorage persistence. */
(function() {
  var toggle = document.getElementById('md-theme-toggle');
  if (!toggle) return;

  // Apply saved preference before paint
  var saved = localStorage.getItem('md-theme');
  if (saved) document.documentElement.setAttribute('data-theme', saved);

  toggle.addEventListener('click', function() {
    var current = document.documentElement.getAttribute('data-theme');
    var isDark = current === 'dark' ||
      (!current && window.matchMedia('(prefers-color-scheme: dark)').matches);
    var next = isDark ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('md-theme', next);
  });

  // The icon itself is swapped by CSS off the resolved theme — see the
  // .md-icon-light / .md-icon-dark rules in the generated token stylesheet.
})();
