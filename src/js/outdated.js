/* ── MaterialDocs: Outdated-version banner ──
   The equivalent of Documenter's warn_outdated. deploydocs() writes
   DOCUMENTER_CURRENT_VERSION and DOCUMENTER_STABLE (siteinfo) and
   DOCUMENTER_NEWEST (the shared version list); when this build is not the newest
   release, or is the development version, say so and link to the same page in
   the stable docs. Only runs on pages built with warn_outdated = true. */
(function() {
  if (!document.body.hasAttribute('data-warn-outdated')) return;
  if (typeof DOCUMENTER_NEWEST === 'undefined' ||
      typeof DOCUMENTER_CURRENT_VERSION === 'undefined' ||
      typeof DOCUMENTER_STABLE === 'undefined') return;
  // Not a version number (e.g. a preview build), so newer/older can't be judged
  if (!/v(\d+\.)*\d+/.test(DOCUMENTER_CURRENT_VERSION)) return;
  if (DOCUMENTER_NEWEST === DOCUMENTER_CURRENT_VERSION) return;

  // Keep search engines on the current docs
  if (!document.querySelector('meta[name="robots"]')) {
    var meta = document.createElement('meta');
    meta.name = 'robots';
    meta.content = 'noindex';
    document.head.appendChild(meta);
  }

  var content = document.querySelector('.md-content');
  var script = document.querySelector('script[src*="materialdocs.js"]');
  if (!content || !script) return;

  // This version's root, from our own script tag, so it works at any depth
  var base = script.getAttribute('src').split('?')[0].replace('assets/materialdocs.js', '') || './';
  var versionRoot = new URL(base, window.location.href).pathname;
  if (versionRoot.charAt(versionRoot.length - 1) !== '/') versionRoot += '/';
  var pagePath = window.location.pathname.indexOf(versionRoot) === 0 ?
    window.location.pathname.substring(versionRoot.length) : '';
  var stableHome = new URL(base + '../' + DOCUMENTER_STABLE + '/', window.location.href).href;

  var isDev = typeof DOCUMENTER_IS_DEV_VERSION !== 'undefined' && DOCUMENTER_IS_DEV_VERSION === true;
  var ICON_INFO = 'M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z';
  var ICON_HISTORY = 'M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z';

  var banner = document.createElement('div');
  banner.className = 'md-outdated-banner' + (isDev ? ' md-outdated-dev' : '');
  banner.setAttribute('role', 'status');
  banner.innerHTML =
    '<svg class="md-icon md-outdated-icon" viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true" focusable="false"><path d="' +
      (isDev ? ICON_INFO : ICON_HISTORY) + '"/></svg>' +
    '<p class="md-outdated-text">' +
      (isDev ? 'This is the documentation for the <strong>development version</strong>, which may contain unreleased features.'
             : 'This is the documentation for an <strong>older version</strong>, which may be missing recent changes.') +
    '</p>' +
    '<div class="md-outdated-actions">' +
      '<button type="button" class="md-text-btn md-outdated-dismiss">Dismiss</button>' +
      '<a class="md-text-btn md-outdated-stable" href="' + stableHome + '">Go to stable</a>' +
    '</div>';

  // Stay on the same page in the stable docs when it exists there
  var stableLink = banner.querySelector('.md-outdated-stable');
  if (pagePath && pagePath !== 'index.html') {
    stableLink.addEventListener('click', function(e) {
      e.preventDefault();
      var target = stableHome + pagePath;
      fetch(target, { method: 'HEAD' })
        .then(function(res) { window.location.href = res.ok ? target + window.location.hash : stableHome; })
        .catch(function() { window.location.href = stableHome; });
    });
  }
  banner.querySelector('.md-outdated-dismiss').addEventListener('click', function() {
    banner.parentNode.removeChild(banner);
  });

  content.insertBefore(banner, content.firstChild);
})();
