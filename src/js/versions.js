/* ── MaterialDocs: Version selector ──
   Reads the metadata Documenter's deploydocs() writes: DOCUMENTER_CURRENT_VERSION
   from siteinfo.js (this build) and DOC_VERSIONS from ../versions.js (every
   deployed version). Both are absent on local builds, so the selector stays
   hidden unless the site has actually been deployed. */
(function() {
  var ICON_CHECK = 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z';

  var wrap = document.getElementById('md-version');
  var btn = document.getElementById('md-version-btn');
  var menu = document.getElementById('md-version-menu');
  var label = document.getElementById('md-version-current');
  if (!wrap || !btn || !menu || !label) return;

  // Explicitly disabled by deploydocs (a non-versioned deployment)
  if (typeof DOCUMENTER_VERSION_SELECTOR_DISABLED !== 'undefined' &&
      DOCUMENTER_VERSION_SELECTOR_DISABLED) return;

  var current = typeof DOCUMENTER_CURRENT_VERSION !== 'undefined' ? DOCUMENTER_CURRENT_VERSION : null;
  var versions = typeof DOC_VERSIONS !== 'undefined' ? DOC_VERSIONS : null;

  // Nothing to switch between — leave the selector hidden
  if (!current && (!versions || !versions.length)) return;

  // Site root, resolved from our own script tag so this works at any page depth
  function resolveBase() {
    var scripts = document.querySelectorAll('script[src*="materialdocs.js"]');
    if (!scripts.length) return './';
    return scripts[0].getAttribute('src').split('?')[0].replace('assets/materialdocs.js', '') || './';
  }

  var base = resolveBase();
  // Absolute path of this version's root directory, always trailing-slashed
  var versionRoot = new URL(base, window.location.href).pathname;
  if (versionRoot.charAt(versionRoot.length - 1) !== '/') versionRoot += '/';

  // The page we're on, relative to the version root — preserved across switches
  var pagePath = window.location.pathname.indexOf(versionRoot) === 0 ?
    window.location.pathname.substring(versionRoot.length) : '';

  function versionURL(version) {
    return new URL(base + '../' + version + '/', window.location.href).href;
  }

  // Try to land on the same page in the target version; fall back to its home
  function go(version) {
    var home = versionURL(version);
    if (!pagePath || pagePath === 'index.html') {
      window.location.href = home;
      return;
    }
    var target = home + pagePath;
    fetch(target, { method: 'HEAD' })
      .then(function(res) {
        window.location.href = res.ok ? target + window.location.hash : home;
      })
      .catch(function() { window.location.href = home; });
  }

  function svg(path) {
    return '<svg class="md-icon" viewBox="0 0 24 24" width="18" height="18" ' +
           'fill="currentColor" aria-hidden="true" focusable="false"><path d="' + path + '"/></svg>';
  }

  // Build the option list: the current version first, then every deployed one
  var entries = [];
  if (current) entries.push(current);
  if (versions) {
    for (var i = 0; i < versions.length; i++) {
      if (entries.indexOf(versions[i]) === -1) entries.push(versions[i]);
    }
  }
  if (!entries.length) return;

  label.textContent = current || entries[0];

  for (var j = 0; j < entries.length; j++) {
    (function(version) {
      var isCurrent = version === current;
      var li = document.createElement('li');
      var item = document.createElement('button');
      item.type = 'button';
      item.className = 'md-version-item';
      item.setAttribute('role', 'option');
      item.setAttribute('aria-selected', isCurrent ? 'true' : 'false');
      item.innerHTML = svg(ICON_CHECK) + '<span>' + version + '</span>';
      if (!isCurrent) item.addEventListener('click', function() { go(version); });
      else item.addEventListener('click', closeMenu);
      li.appendChild(item);
      menu.appendChild(li);
    })(entries[j]);
  }

  function openMenu() {
    menu.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    document.addEventListener('click', onDocClick);
  }

  function closeMenu() {
    menu.hidden = true;
    btn.setAttribute('aria-expanded', 'false');
    document.removeEventListener('click', onDocClick);
  }

  function onDocClick(e) {
    if (!wrap.contains(e.target)) closeMenu();
  }

  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    menu.hidden ? openMenu() : closeMenu();
  });

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && !menu.hidden) { closeMenu(); btn.focus(); }
  });

  // Everything resolved — reveal the selector
  wrap.hidden = false;
})();
