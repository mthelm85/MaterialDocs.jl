/* ── MaterialDocs: Search ──
   MD3 search bar → search view. The navbar bar morphs into a view that is
   docked beneath it on wide windows and full-screen on compact ones. */
(function() {
  var COMPACT = 768;
  var ICON_SEARCH = 'M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z';
  var ICON_BACK = 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z';
  var ICON_CLOSE = 'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z';

  var bar = document.getElementById('md-search-btn');
  if (!bar) return;

  var view = null, scrim = null, input = null, results = null, leadBtn = null, clearBtn = null;
  var index = null, items = [], selected = -1, basePath = '';

  function svg(path) {
    return '<svg class="md-icon" viewBox="0 0 24 24" width="20" height="20" ' +
           'fill="currentColor" aria-hidden="true" focusable="false"><path d="' + path + '"/></svg>';
  }

  function isCompact() { return window.innerWidth <= COMPACT; }

  // Resolve the site root from our own script tag, so search works at any depth
  function resolveBase() {
    var scripts = document.querySelectorAll('script[src*="materialdocs.js"]');
    if (!scripts.length) return '';
    var src = scripts[0].getAttribute('src').split('?')[0];
    return src.replace('assets/materialdocs.js', '');
  }

  function loadIndex() {
    if (index !== null) return;
    var xhr = new XMLHttpRequest();
    xhr.open('GET', basePath + 'assets/search-index.json', true);
    xhr.onload = function() {
      if (xhr.status === 200) {
        try { index = JSON.parse(xhr.responseText); } catch (e) { index = []; }
      } else { index = []; }
      if (input && input.value) search(input.value);
    };
    xhr.onerror = function() { index = []; };
    xhr.send();
  }

  function build() {
    if (view) return;

    scrim = document.createElement('div');
    scrim.className = 'md-search-scrim';
    document.body.appendChild(scrim);

    view = document.createElement('div');
    view.className = 'md-search-view';
    view.setAttribute('role', 'dialog');
    view.setAttribute('aria-label', 'Search documentation');
    view.innerHTML =
      '<div class="md-search-view-header">' +
        '<button class="md-icon-btn md-search-lead" aria-label="Close search"></button>' +
        '<input class="md-search-input" type="text" autocomplete="off" spellcheck="false" ' +
               'placeholder="Search docs" aria-label="Search documentation">' +
        '<button class="md-icon-btn md-search-clear" aria-label="Clear search" hidden>' + svg(ICON_CLOSE) + '</button>' +
      '</div>' +
      '<div class="md-search-results"></div>';
    document.body.appendChild(view);

    input = view.querySelector('.md-search-input');
    results = view.querySelector('.md-search-results');
    leadBtn = view.querySelector('.md-search-lead');
    clearBtn = view.querySelector('.md-search-clear');

    scrim.addEventListener('click', close);
    leadBtn.addEventListener('click', close);
    clearBtn.addEventListener('click', function() {
      input.value = '';
      search('');
      input.focus();
    });
    input.addEventListener('input', function() { search(input.value); });
    input.addEventListener('keydown', onKeydown);
    window.addEventListener('resize', function() {
      if (view.classList.contains('md-search-active')) position();
    });
  }

  // Anchor the docked view to the search bar so it reads as a morph
  function position() {
    if (isCompact()) {
      view.style.removeProperty('--md-search-left');
      view.style.removeProperty('--md-search-width');
      view.style.removeProperty('--md-search-top');
      return;
    }
    var r = bar.getBoundingClientRect();
    var width = Math.min(Math.max(r.width, 384), window.innerWidth - 32);
    // Right-align with the bar, but never overflow the viewport
    var left = Math.min(Math.max(8, r.right - width), window.innerWidth - width - 8);
    view.style.setProperty('--md-search-top', (r.bottom + 8) + 'px');
    view.style.setProperty('--md-search-left', left + 'px');
    view.style.setProperty('--md-search-width', width + 'px');
  }

  function open() {
    build();
    basePath = resolveBase();
    loadIndex();
    // Compact windows get a back arrow; docked keeps the search glyph
    leadBtn.innerHTML = svg(isCompact() ? ICON_BACK : ICON_SEARCH);
    position();
    view.classList.add('md-search-active');
    scrim.classList.add('md-search-active');
    bar.setAttribute('aria-expanded', 'true');
    selected = -1;
    requestAnimationFrame(function() { input.focus(); input.select(); });
  }

  function close() {
    if (!view) return;
    view.classList.remove('md-search-active');
    scrim.classList.remove('md-search-active');
    bar.setAttribute('aria-expanded', 'false');
    bar.focus();
  }

  function isOpen() {
    return view && view.classList.contains('md-search-active');
  }

  function onKeydown(e) {
    if (e.key === 'Escape') { close(); e.preventDefault(); }
    else if (e.key === 'ArrowDown') { move(1); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { move(-1); e.preventDefault(); }
    else if (e.key === 'Enter' && selected >= 0 && selected < items.length) {
      window.location.href = items[selected].href;
      e.preventDefault();
    }
  }

  function escHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  // Highlight every occurrence of the query within already-escaped text
  function highlight(text, query) {
    if (!query) return escHtml(text);
    var escaped = escHtml(text);
    var qEsc = escHtml(query).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return escaped.replace(new RegExp('(' + qEsc + ')', 'gi'), '<mark class="md-search-mark">$1</mark>');
  }

  // Pull a readable window of text around the first match
  function snippet(text, query) {
    if (!text) return '';
    var idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return '';
    var start = Math.max(0, idx - 40);
    var end = Math.min(text.length, idx + query.length + 80);
    if (start > 0) {
      var ws = text.indexOf(' ', start);
      if (ws !== -1 && ws < idx) start = ws + 1;
    }
    if (end < text.length) {
      var ws2 = text.lastIndexOf(' ', end);
      if (ws2 > idx + query.length) end = ws2;
    }
    return (start > 0 ? '…' : '') + text.substring(start, end) + (end < text.length ? '…' : '');
  }

  function search(query) {
    selected = -1;
    items = [];
    clearBtn.hidden = !query;

    if (!query) { results.innerHTML = ''; return; }
    if (index === null) {
      results.innerHTML = '<div class="md-search-empty">Loading…</div>';
      return;
    }

    var q = query.toLowerCase();
    var matches = [];
    for (var i = 0; i < index.length; i++) {
      var entry = index[i];
      var title = (entry.title || '').toLowerCase();
      var text = (entry.text || '').toLowerCase();
      var score = 0;
      if (title === q) score += 20;
      if (title.indexOf(q) !== -1) score += 10;
      if (text.indexOf(q) !== -1) score += 1;
      if (score > 0) matches.push({ entry: entry, score: score });
    }
    matches.sort(function(a, b) { return b.score - a.score; });
    items = matches.slice(0, 20);

    var html = '';
    for (var j = 0; j < items.length; j++) {
      var e = items[j].entry;
      items[j].href = basePath + (e.href || '#');
      var snip = snippet(e.text || '', query);
      html += '<a class="md-search-item" href="' + escHtml(items[j].href) + '" role="option">' +
        '<span class="md-search-item-title">' + highlight(e.title || '', query) + '</span>' +
        (e.section ? '<span class="md-search-item-section">' + escHtml(e.section) + '</span>' : '') +
        (snip ? '<span class="md-search-item-snippet">' + highlight(snip, query) + '</span>' : '') +
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

  bar.addEventListener('click', function() { isOpen() ? close() : open(); });

  document.addEventListener('keydown', function(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      isOpen() ? close() : open();
    } else if (e.key === 'Escape' && isOpen()) {
      close();
    }
  });
})();
