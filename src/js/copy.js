/* ── MaterialDocs: Copy Code ──
   Clipboard copy for code blocks with visual feedback. */
(function() {
  document.addEventListener('click', function(e) {
    var btn = e.target.closest('.md-copy-btn');
    if (!btn) return;
    var block = btn.closest('.md-code-block');
    if (!block) return;
    var code = block.querySelector('code');
    if (!code) return;

    var text = code.textContent;
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text).then(function() {
        showCopied(btn);
      });
    } else {
      // Fallback for older browsers / non-HTTPS
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); showCopied(btn); }
      catch(err) { /* silently fail */ }
      document.body.removeChild(ta);
    }
  });

  function showCopied(btn) {
    btn.classList.add('copied');
    setTimeout(function() { btn.classList.remove('copied'); }, 1500);
  }
})();
