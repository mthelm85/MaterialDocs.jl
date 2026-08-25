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
  // Multi-page sites have .md-sidebar; single-page sites only have .md-toc
  var sidebar = document.querySelector('.md-sidebar');
  var toc = document.querySelector('.md-toc');
  var panel = sidebar || toc;

  if (hamburger && panel) {
    // Create scrim overlay
    var scrim = document.createElement('div');
    scrim.className = 'md-sidebar-scrim';
    document.body.appendChild(scrim);

    // If using TOC as the mobile panel, add the sidebar positioning classes
    if (!sidebar && toc) {
      toc.classList.add('md-mobile-nav');
    }

    function openPanel() {
      panel.classList.add('md-sidebar-open');
      scrim.classList.add('active');
      hamburger.setAttribute('aria-expanded', 'true');
    }

    function closePanel() {
      panel.classList.remove('md-sidebar-open');
      scrim.classList.remove('active');
      hamburger.setAttribute('aria-expanded', 'false');
    }

    hamburger.addEventListener('click', function() {
      if (panel.classList.contains('md-sidebar-open')) {
        closePanel();
      } else {
        openPanel();
      }
    });

    // Close when clicking scrim
    scrim.addEventListener('click', closePanel);

    // Close when clicking a link inside the panel
    panel.addEventListener('click', function(e) {
      if (e.target.tagName === 'A') {
        closePanel();
      }
    });
  }
})();
