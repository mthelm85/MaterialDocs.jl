/* ── MaterialDocs: TOC Scroll Spy ──
   Highlights the active heading in the right-rail table of contents.
   Listens on .md-content (the scrollable content column). */
(function() {
  var links = document.querySelectorAll('.md-toc-link');
  if (!links.length) return;

  var content = document.querySelector('.md-content');
  if (!content) return;

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
    var scrollTop = content.scrollTop;
    var current = null;
    for (var i = 0; i < headings.length; i++) {
      // offsetTop is relative to offsetParent; subtract content's offset
      var top = headings[i].el.offsetTop - content.offsetTop;
      if (top - OFFSET <= scrollTop) {
        current = headings[i];
      }
    }
    // At bottom of scrollable area, activate last heading
    if (content.scrollTop + content.clientHeight >= content.scrollHeight - 2) {
      current = headings[headings.length - 1];
    }
    if (current !== active) {
      if (active) active.link.classList.remove('active');
      if (current) current.link.classList.add('active');
      active = current;
    }
  }

  // Throttled scroll handler on the content column
  var ticking = false;
  content.addEventListener('scroll', function() {
    if (!ticking) {
      requestAnimationFrame(function() { update(); ticking = false; });
      ticking = true;
    }
  }, { passive: true });

  // Smooth scroll on TOC click — scroll only the content column
  for (var j = 0; j < links.length; j++) {
    links[j].addEventListener('click', function(e) {
      var href = this.getAttribute('href');
      if (href && href.charAt(0) === '#') {
        var target = document.getElementById(href.slice(1));
        if (target) {
          e.preventDefault();
          // Manually compute scroll position within content column
          // to avoid scrollIntoView nudging other containers
          var targetTop = target.offsetTop - content.offsetTop;
          content.scrollTo({ top: targetTop, behavior: 'smooth' });
          history.replaceState(null, '', href);
        }
      }
    });
  }

  // Intercept all hash-link clicks within content to prevent body scroll
  content.addEventListener('click', function(e) {
    var link = e.target.closest('a[href^="#"]');
    if (!link) return;
    var id = link.getAttribute('href').slice(1);
    var target = document.getElementById(id);
    if (target) {
      e.preventDefault();
      var targetTop = target.offsetTop - content.offsetTop;
      content.scrollTo({ top: targetTop, behavior: 'smooth' });
      history.replaceState(null, '', '#' + id);
    }
  });

  update(); // initial state
})();
