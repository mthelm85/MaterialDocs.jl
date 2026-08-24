/* ── MaterialDocs: TOC Scroll Spy ──
   Highlights the active heading in the right-rail table of contents. */
(function() {
  var links = document.querySelectorAll('.md-toc-link');
  if (!links.length) return;

  // Build heading list from TOC hrefs
  var headings = [];
  for (var i = 0; i < links.length; i++) {
    var href = links[i].getAttribute('href');
    if (href && href.charAt(0) === '#') {
      var el = document.getElementById(href.slice(1));
      if (el) headings.push({ el: el, link: links[i] });
    }
  }
  if (!headings.length) return;

  var active = null;
  var OFFSET = 80; // pixels below top to trigger

  function update() {
    var scrollY = window.scrollY || window.pageYOffset;
    var current = null;
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].el.offsetTop - OFFSET <= scrollY) {
        current = headings[i];
      }
    }
    // At bottom of page, activate last heading
    if (window.innerHeight + scrollY >= document.body.scrollHeight - 2) {
      current = headings[headings.length - 1];
    }
    if (current !== active) {
      if (active) active.link.classList.remove('active');
      if (current) current.link.classList.add('active');
      active = current;
    }
  }

  // Throttled scroll handler
  var ticking = false;
  window.addEventListener('scroll', function() {
    if (!ticking) {
      requestAnimationFrame(function() { update(); ticking = false; });
      ticking = true;
    }
  }, { passive: true });

  // Smooth scroll on TOC click
  for (var j = 0; j < links.length; j++) {
    links[j].addEventListener('click', function(e) {
      var href = this.getAttribute('href');
      if (href && href.charAt(0) === '#') {
        var target = document.getElementById(href.slice(1));
        if (target) {
          e.preventDefault();
          target.scrollIntoView({ behavior: 'smooth', block: 'start' });
          history.replaceState(null, '', href);
        }
      }
    });
  }

  update(); // initial state
})();
