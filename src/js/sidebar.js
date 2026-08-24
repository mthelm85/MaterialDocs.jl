/* ── MaterialDocs: Sidebar ──
   Collapsible nav sections and mobile hamburger menu. */
(function() {
  // ── Collapsible sections ──
  var titles = document.querySelectorAll('.md-nav-section-title');
  for (var i = 0; i < titles.length; i++) {
    (function(title) {
      var section = title.parentElement;
      var key = 'md-nav-' + title.textContent.trim().toLowerCase().replace(/\s+/g, '-');
      // Restore collapsed state
      if (localStorage.getItem(key) === 'collapsed') {
        section.classList.add('md-nav-collapsed');
      }
      title.style.cursor = 'pointer';
      title.setAttribute('role', 'button');
      title.setAttribute('aria-expanded', !section.classList.contains('md-nav-collapsed'));
      title.addEventListener('click', function() {
        var collapsed = section.classList.toggle('md-nav-collapsed');
        title.setAttribute('aria-expanded', !collapsed);
        localStorage.setItem(key, collapsed ? 'collapsed' : 'expanded');
      });
    })(titles[i]);
  }

  // ── Mobile hamburger ──
  var hamburger = document.getElementById('md-hamburger');
  var sidebar = document.querySelector('.md-sidebar');
  if (hamburger && sidebar) {
    hamburger.addEventListener('click', function() {
      var open = sidebar.classList.toggle('md-sidebar-open');
      hamburger.setAttribute('aria-expanded', open);
    });
    // Close sidebar when clicking a link (mobile)
    sidebar.addEventListener('click', function(e) {
      if (e.target.tagName === 'A') {
        sidebar.classList.remove('md-sidebar-open');
        hamburger.setAttribute('aria-expanded', 'false');
      }
    });
  }
})();
