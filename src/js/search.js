/* ── MaterialDocs: Search ──
   Command palette search overlay with keyboard navigation. */
(function() {
  var overlay = null;
  var input = null;
  var results = null;
  var index = null;
  var items = [];
  var selected = -1;

  // Load search index lazily
  function loadIndex(base) {
    if (index !== null) return;
    var xhr = new XMLHttpRequest();
    xhr.open('GET', base + 'assets/search-index.json', true);
    xhr.onload = function() {
      if (xhr.status === 200) {
        try { index = JSON.parse(xhr.responseText); }
        catch(e) { index = []; }
      } else { index = []; }
    };
    xhr.onerror = function() { index = []; };
    xhr.send();
  }

  function createOverlay() {
    if (overlay) return;
    overlay = document.createElement('div');
    overlay.className = 'md-search-overlay';
    overlay.innerHTML =
      '<div class="md-search-modal">' +
        '<input class="md-search-input" type="text" placeholder="Search docs…" aria-label="Search documentation">' +
        '<div class="md-search-results"></div>' +
        '<div class="md-search-hint">↑↓ navigate · ↵ open · esc close</div>' +
      '</div>';
    document.body.appendChild(overlay);
    input = overlay.querySelector('.md-search-input');
    results = overlay.querySelector('.md-search-results');

    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) close();
    });
    input.addEventListener('input', function() { search(input.value); });
    input.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { close(); e.preventDefault(); }
      else if (e.key === 'ArrowDown') { move(1); e.preventDefault(); }
      else if (e.key === 'ArrowUp') { move(-1); e.preventDefault(); }
      else if (e.key === 'Enter' && selected >= 0 && selected < items.length) {
        window.location.href = items[selected].href;
        close();
        e.preventDefault();
      }
    });
  }

  function open() {
    createOverlay();
    overlay.classList.add('md-search-active');
    input.value = '';
    results.innerHTML = '';
    items = [];
    selected = -1;
    // Determine base path from the page's script tag
    var scripts = document.querySelectorAll('script[src*="materialdocs.js"]');
    var base = '';
    if (scripts.length) {
      var src = scripts[0].getAttribute('src');
      base = src.replace('assets/materialdocs.js', '');
    }
    loadIndex(base);
    requestAnimationFrame(function() { input.focus(); });
  }

  function close() {
    if (overlay) overlay.classList.remove('md-search-active');
  }

  function search(query) {
    selected = -1;
    if (!query || !index || !index.length) {
      results.innerHTML = index === null ? '<div class="md-search-empty">Loading…</div>' :
        query ? '<div class="md-search-empty">No results</div>' : '';
      items = [];
      return;
    }
    var q = query.toLowerCase();
    var matches = [];
    for (var i = 0; i < index.length; i++) {
      var entry = index[i];
      var title = (entry.title || '').toLowerCase();
      var text = (entry.text || '').toLowerCase();
      var score = 0;
      if (title.indexOf(q) !== -1) score += 10;
      if (text.indexOf(q) !== -1) score += 1;
      if (title === q) score += 20;
      if (score > 0) matches.push({ entry: entry, score: score });
    }
    matches.sort(function(a, b) { return b.score - a.score; });
    items = matches.slice(0, 20);
    var html = '';
    for (var j = 0; j < items.length; j++) {
      var e = items[j].entry;
      items[j].href = e.href || '#';
      html += '<a class="md-search-item" href="' + escHtml(items[j].href) + '">' +
        '<span class="md-search-item-title">' + escHtml(e.title || '') + '</span>' +
        (e.section ? '<span class="md-search-item-section">' + escHtml(e.section) + '</span>' : '') +
        '</a>';
    }
    results.innerHTML = html || '<div class="md-search-empty">No results</div>';
  }

  function move(dir) {
    var elems = results.querySelectorAll('.md-search-item');
    if (!elems.length) return;
    if (selected >= 0 && selected < elems.length) elems[selected].classList.remove('md-search-selected');
    selected = Math.max(0, Math.min(elems.length - 1, selected + dir));
    elems[selected].classList.add('md-search-selected');
    elems[selected].scrollIntoView({ block: 'nearest' });
  }

  function escHtml(s) {
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  // Keyboard shortcut: Cmd/Ctrl+K
  document.addEventListener('keydown', function(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      if (overlay && overlay.classList.contains('md-search-active')) close();
      else open();
    }
  });

  // Search button click
  var searchBtn = document.getElementById('md-search-btn');
  if (searchBtn) searchBtn.addEventListener('click', open);
})();
