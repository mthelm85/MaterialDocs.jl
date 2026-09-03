#=
Theme Editor — interactive browser-based theme configurator.

`MaterialDocs.editor()` serves the actual built docs with a floating theme
editor panel injected. Since all CSS uses `var(--md-sys-*)` tokens, changing
the custom properties instantly re-themes the real documentation.
=#

import Sockets: listen, accept, IPv4, TCPSocket, getsockname

"""
    editor(; build="docs/build", port=0, theme=resolve_theme(:default))

Launch the MaterialDocs theme editor — a local server that serves your
actual built documentation with a floating theme editor panel injected.

# Workflow
1. Build your docs: `julia --project=docs docs/make.jl`
2. Launch the editor: `MaterialDocs.editor(build="docs/build")`
3. Tweak colors, fonts, and shape in the panel — changes apply live
4. Click **Copy TOML** to export your configuration

The editor modifies CSS custom properties on `:root`, which instantly
re-themes every component since all styles use `var(--md-sys-*)` tokens.

# Keywords
- `build`: path to the built docs directory (default `"docs/build"`)
- `port`: server port; `0` picks an available port automatically
- `theme`: initial `ThemeConfig` for the editor panel defaults

# Example
```julia
using MaterialDocs

# After running makedocs:
MaterialDocs.editor()

# Or with a specific build dir and theme:
MaterialDocs.editor(build="docs/build", theme=resolve_theme(:ocean_depth))
```

Press Ctrl+C in the REPL to stop the server.
"""
function editor(; build::String="docs/build",
                  port::Int=0,
                  theme::ThemeConfig=resolve_theme(:default),
                  make::Union{AbstractString,Nothing}="docs/make.jl")
    # Rebuild first so the editor always reflects the current sources
    if make !== nothing
        if isfile(make)
            proj = isempty(dirname(make)) ? "." : dirname(make)
            @info "MaterialDocs: building docs before serving" script=make project=proj
            try
                run(`$(Base.julia_cmd()) --project=$proj $make`)
            catch
                error("Docs build failed: $make. Fix the build, or pass " *
                      "make=nothing to serve the existing build directory.")
            end
        else
            @warn "MaterialDocs: no build script found; serving the existing build" script=make
        end
    end

    # Validate build directory
    if !isdir(build)
        error("Build directory not found: $(abspath(build))\n" *
              "Run makedocs first, then call editor(build=\"path/to/build\")")
    end
    if !isfile(joinpath(build, "index.html"))
        error("No index.html found in $(abspath(build))\n" *
              "This doesn't look like a Documenter build directory.")
    end

    build_abs = abspath(build)
    panel_html = _editor_panel_html(theme)
    panel_js = _editor_panel_js(theme)

    # Start server
    server = listen(IPv4(0), port)
    actual_port = Int(getsockname(server)[2])
    url = "http://localhost:$actual_port"

    @info "MaterialDocs theme editor" url build=build_abs
    @info "Press Ctrl+C to stop"

    _open_in_browser(url)

    # Serve requests
    try
        while true
            sock = accept(server)
            @async _handle_request(sock, build_abs, panel_html, panel_js)
        end
    catch e
        if !(e isa InterruptException)
            rethrow(e)
        end
    finally
        close(server)
        @info "MaterialDocs editor stopped"
    end
end

"""Open a URL in the default browser (cross-platform)."""
function _open_in_browser(url::String)
    try
        if Sys.iswindows()
            run(`cmd /c start "" "$url"`)
        elseif Sys.isapple()
            run(`open "$url"`)
        else
            run(`xdg-open "$url"`)
        end
    catch
        @warn "Could not open browser automatically. Open $url manually."
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# HTTP server (minimal, stdlib-only)
# ─────────────────────────────────────────────────────────────────────────────

"""Handle one HTTP request."""
function _handle_request(sock::TCPSocket, build_dir::String,
                         panel_html::String, panel_js::String)
    try
        # Read request line
        request_line = readline(sock)
        isempty(request_line) && return close(sock)

        # Parse method and path
        parts = split(request_line)
        length(parts) < 2 && return close(sock)
        method = parts[1]
        raw_path = parts[2]

        # Read and discard headers
        while true
            line = readline(sock)
            (isempty(line) || line == "\r") && break
        end

        # Only handle GET
        if method != "GET"
            _send_response(sock, 405, "text/plain", "Method Not Allowed")
            return
        end

        # Decode path
        path = _url_decode(split(raw_path, '?')[1])  # strip query string
        path == "/" && (path = "/index.html")

        # Security: prevent directory traversal
        if contains(path, "..") || contains(path, "\\")
            _send_response(sock, 403, "text/plain", "Forbidden")
            return
        end

        # Special route: editor panel JS (served separately to keep injection small)
        if path == "/__editor__.js"
            _send_response(sock, 200, "application/javascript", panel_js)
            return
        end

        # Resolve file
        file_path = joinpath(build_dir, lstrip(path, '/'))
        # If path is a directory, try index.html
        if isdir(file_path)
            file_path = joinpath(file_path, "index.html")
        end

        if !isfile(file_path)
            _send_response(sock, 404, "text/plain", "Not Found: $path")
            return
        end

        content_type = _mime_type(file_path)

        if endswith(file_path, ".html")
            # Inject editor panel into HTML pages
            html = read(file_path, String)
            html = _inject_editor(html, panel_html)
            _send_response(sock, 200, content_type, html)
        else
            # Serve binary/text files as-is
            _send_response(sock, 200, content_type, read(file_path))
        end
    catch e
        e isa EOFError || @debug "Request handler error" exception=e
    finally
        try close(sock) catch end
    end
end

"""Send an HTTP response."""
function _send_response(sock::TCPSocket, status::Int, content_type::String,
                        body::Union{String,Vector{UInt8}})
    status_text = Dict(200=>"OK", 403=>"Forbidden", 404=>"Not Found",
                       405=>"Method Not Allowed")
    data = body isa String ? Vector{UInt8}(body) : body
    write(sock, "HTTP/1.1 $status $(get(status_text, status, ""))\r\n")
    write(sock, "Content-Type: $content_type\r\n")
    write(sock, "Content-Length: $(length(data))\r\n")
    write(sock, "Connection: close\r\n")
    write(sock, "Cache-Control: no-cache\r\n")
    write(sock, "\r\n")
    write(sock, data)
end

"""URL-decode a path string."""
function _url_decode(s::AbstractString)::String
    replace(s, r"%([0-9A-Fa-f]{2})" => m -> Char(parse(UInt8, m[2:3]; base=16)))
end

"""Get MIME type from file extension."""
function _mime_type(path::String)::String
    ext = lowercase(splitext(path)[2])
    types = Dict(
        ".html" => "text/html; charset=utf-8",
        ".css"  => "text/css; charset=utf-8",
        ".js"   => "application/javascript; charset=utf-8",
        ".json" => "application/json; charset=utf-8",
        ".png"  => "image/png",
        ".jpg"  => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif"  => "image/gif",
        ".svg"  => "image/svg+xml",
        ".ico"  => "image/x-icon",
        ".woff" => "font/woff",
        ".woff2"=> "font/woff2",
        ".ttf"  => "font/ttf",
    )
    get(types, ext, "application/octet-stream")
end

# ─────────────────────────────────────────────────────────────────────────────
# Editor panel injection
# ─────────────────────────────────────────────────────────────────────────────

"""Inject the editor panel HTML + JS loader into an HTML page."""
function _inject_editor(html::String, panel_html::String)::String
    # The panel script is large (it carries the whole HCT engine) and loads as
    # an external resource, so it lands well after first paint. On navigation
    # that shows the built-in theme before the edited one — the theme appears
    # to reset. This head script re-applies the last-applied tokens from a
    # cache written by the panel, synchronously, before anything is painted.
    head_script = """
    <script>
    (function(){
      var root = document.documentElement;
      // Restore the editor's light/dark choice. The built-in restore script
      // only exists when the site was built with dark_mode = :toggle, so the
      // editor has to do this itself to work against any build.
      try {
        var t = localStorage.getItem('md-theme');
        if (t) root.setAttribute('data-theme', t);
      } catch(e) {}
      try {
        var c = sessionStorage.getItem('__md_editor_css__');
        if (!c) return;
        var data = JSON.parse(c);
        if (!data || !data.vars) return;
        // Cached tokens are mode-specific; skip them if the mode has since
        // changed and let the panel recompute rather than flash wrong colors.
        var attr = root.getAttribute('data-theme');
        var dark = attr === 'dark' ? true : attr === 'light' ? false :
          window.matchMedia('(prefers-color-scheme: dark)').matches;
        if (data.mode !== (dark ? 'dark' : 'light')) return;
        for (var k in data.vars) root.style.setProperty(k, data.vars[k]);
      } catch(e) {}
    })()
    </script>
    """

    # Inject panel before </body>, and load the editor JS
    injection = """
    $panel_html
    <script src="/__editor__.js"></script>
    """

    out = contains(html, "</head>") ?
        replace(html, "</head>" => head_script * "\n</head>"; count=1) : html

    if contains(out, "</body>")
        replace(out, "</body>" => injection * "\n</body>")
    else
        out * injection
    end
end

"""Generate the floating editor panel HTML."""
function _editor_panel_html(theme::ThemeConfig)::String
    sec_seed = something(theme.secondary_seed, theme.seed)
    ter_seed = something(theme.tertiary_seed, theme.seed)

    """
    <style>$(_editor_panel_css())</style>
    <div id="md-editor-panel" class="md-editor-panel md-editor-collapsed">
      <button id="md-editor-toggle" class="md-editor-tab" title="Theme Editor">🎨</button>
      <div class="md-editor-body">
        <div class="md-editor-header">
          <h3>Theme Editor</h3>
          <button id="md-editor-close" class="md-editor-close">✕</button>
        </div>

        <div class="md-editor-scroll">
          <section class="md-editor-section">
            <h4>Seed Color</h4>
            <div class="md-editor-field">
              <label>All colors are generated from this</label>
              <div class="md-editor-color-row">
                <input type="color" id="ed-seed" value="$(theme.seed)">
                <input type="text" id="ed-seed-hex" value="$(theme.seed)" class="md-editor-hex">
              </div>
            </div>
            <div id="ed-palette" class="md-editor-palette"></div>
            <details class="md-editor-overrides">
              <summary>Color overrides</summary>
              <div class="md-editor-field">
                <label>Background</label>
                <div class="md-editor-color-row">
                  <input type="color" id="ed-bg" value="#f8faf8">
                  <input type="text" id="ed-bg-hex" value="" class="md-editor-hex" placeholder="auto">
                </div>
              </div>
              <div class="md-editor-field">
                <label>Text</label>
                <div class="md-editor-color-row">
                  <input type="color" id="ed-text" value="#191c1b">
                  <input type="text" id="ed-text-hex" value="" class="md-editor-hex" placeholder="auto">
                </div>
              </div>
              <div class="md-editor-field">
                <label>Secondary seed</label>
                <div class="md-editor-color-row">
                  <input type="color" id="ed-secondary" value="$(sec_seed)">
                  <input type="text" id="ed-secondary-hex" value="" class="md-editor-hex" placeholder="auto">
                </div>
              </div>
              <div class="md-editor-field">
                <label>Tertiary seed</label>
                <div class="md-editor-color-row">
                  <input type="color" id="ed-tertiary" value="$(ter_seed)">
                  <input type="text" id="ed-tertiary-hex" value="" class="md-editor-hex" placeholder="auto">
                </div>
              </div>
            </details>
          </section>

          <section class="md-editor-section">
            <h4>Typography</h4>
            <div class="md-editor-field">
              <label>Display</label>
              <select id="ed-display-font">$(_font_options(theme.display_font, :display))</select>
            </div>
            <div class="md-editor-field">
              <label>Body</label>
              <select id="ed-body-font">$(_font_options(theme.body_font, :body))</select>
            </div>
            <div class="md-editor-field">
              <label>Code</label>
              <select id="ed-code-font">$(_font_options(theme.code_font, :code))</select>
            </div>
          </section>

          <section class="md-editor-section">
            <h4>Shape</h4>
            <div class="md-editor-field">
              <label>Corners</label>
              <select id="ed-corner-radius">
                <option value="sharp"$(_sel(theme.corner_radius, :sharp))>Sharp</option>
                <option value="default"$(_sel(theme.corner_radius, :default))>Default</option>
                <option value="rounded"$(_sel(theme.corner_radius, :rounded))>Rounded</option>
                <option value="pill"$(_sel(theme.corner_radius, :pill))>Pill</option>
              </select>
            </div>
          </section>

          <section class="md-editor-section">
            <h4>Dark Mode</h4>
            <div class="md-editor-field">
              <button id="ed-toggle-dark" class="md-editor-btn">🌙 Toggle Dark</button>
            </div>
          </section>

          <section class="md-editor-section">
            <h4>Export</h4>
            <button id="ed-copy-toml" class="md-editor-btn md-editor-btn-primary">📋 Copy TOML</button>
            <pre id="ed-toml-preview" class="md-editor-toml"></pre>
          </section>
        </div>
      </div>
    </div>
    """
end

"""Generate select option for whether it's selected."""
function _sel(current::Symbol, value::Symbol)::String
    current == value ? " selected" : ""
end

"""Generate font <option> elements."""
function _font_options(current::String, category::Symbol)::String
    fonts = if category == :code
        ["JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono",
         "IBM Plex Mono", "Inconsolata", "Ubuntu Mono", "Cascadia Code"]
    elseif category == :display
        ["Roboto", "Inter", "Open Sans", "Lato", "Poppins", "Montserrat",
         "Nunito", "Raleway", "Playfair Display", "Merriweather", "Fraunces"]
    else
        ["Roboto", "Inter", "Open Sans", "Lato", "Noto Sans", "Source Sans 3",
         "IBM Plex Sans", "Nunito", "Literata", "Lora", "Crimson Text"]
    end
    current in fonts || pushfirst!(fonts, current)
    io = IOBuffer()
    for f in fonts
        sel = f == current ? " selected" : ""
        println(io, "<option value=\"$f\"$sel>$f</option>")
    end
    String(take!(io))
end

"""CSS for the floating editor panel."""
function _editor_panel_css()::String
    """
    .md-editor-panel {
      position: fixed;
      top: 0;
      right: 0;
      height: 100vh;
      z-index: 10000;
      display: flex;
      font-family: system-ui, -apple-system, sans-serif;
      pointer-events: none;
    }
    .md-editor-panel > * { pointer-events: auto; }
    .md-editor-tab {
      position: absolute;
      right: 0;
      top: 50%;
      transform: translateY(-50%) translateX(0);
      background: #1a73e8;
      color: #fff;
      border: none;
      border-radius: 8px 0 0 8px;
      padding: 0.75rem 0.5rem;
      cursor: pointer;
      font-size: 1.25rem;
      box-shadow: -2px 0 8px rgba(0,0,0,0.2);
      z-index: 1;
      transition: right 0.3s ease;
    }
    .md-editor-collapsed .md-editor-body { transform: translateX(100%); }
    .md-editor-collapsed .md-editor-tab { right: 0; }
    .md-editor-panel:not(.md-editor-collapsed) .md-editor-tab { right: 320px; }
    .md-editor-body {
      width: 320px;
      height: 100vh;
      background: #fff;
      border-left: 1px solid #e0e0e0;
      box-shadow: -4px 0 12px rgba(0,0,0,0.1);
      display: flex;
      flex-direction: column;
      transition: transform 0.3s ease;
      margin-left: auto;
    }
    .md-editor-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0.75rem 1rem;
      border-bottom: 1px solid #e0e0e0;
    }
    .md-editor-header h3 { font-size: 1rem; margin: 0; }
    .md-editor-close {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 1.25rem;
      color: #666;
      padding: 0.25rem;
    }
    .md-editor-scroll {
      flex: 1;
      overflow-y: auto;
      padding: 1rem;
    }
    .md-editor-section {
      margin-bottom: 1.25rem;
    }
    .md-editor-section h4 {
      font-size: 0.6875rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: #888;
      margin: 0 0 0.5rem 0;
    }
    .md-editor-field {
      margin-bottom: 0.5rem;
    }
    .md-editor-field label {
      display: block;
      font-size: 0.75rem;
      font-weight: 500;
      margin-bottom: 0.125rem;
      color: #555;
    }
    .md-editor-field select {
      width: 100%;
      padding: 0.3rem 0.5rem;
      border: 1px solid #ccc;
      border-radius: 4px;
      font-size: 0.8125rem;
      background: #fff;
    }
    .md-editor-color-row {
      display: flex;
      gap: 0.375rem;
      align-items: center;
    }
    .md-editor-color-row input[type="color"] {
      width: 32px;
      height: 28px;
      border: 1px solid #ccc;
      border-radius: 4px;
      padding: 1px;
      cursor: pointer;
    }
    .md-editor-hex {
      flex: 1;
      font-family: monospace;
      font-size: 0.8125rem;
      padding: 0.25rem 0.375rem;
      border: 1px solid #ccc;
      border-radius: 4px;
    }
    .md-editor-palette {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 3px;
      margin: 0.5rem 0;
    }
    .md-editor-swatch {
      height: 24px;
      border-radius: 3px;
      border: 1px solid rgba(0,0,0,0.1);
      position: relative;
      cursor: default;
    }
    .md-editor-swatch[title]:hover::after {
      content: attr(title);
      position: absolute;
      bottom: 100%;
      left: 50%;
      transform: translateX(-50%);
      background: #333;
      color: #fff;
      font-size: 0.625rem;
      padding: 2px 5px;
      border-radius: 3px;
      white-space: nowrap;
      z-index: 10;
      pointer-events: none;
    }
    .md-editor-overrides {
      margin-top: 0.5rem;
    }
    .md-editor-overrides summary {
      font-size: 0.75rem;
      color: #666;
      cursor: pointer;
      user-select: none;
    }
    .md-editor-overrides summary:hover { color: #333; }
    .md-editor-overrides[open] { margin-bottom: 0.25rem; }
    .md-editor-btn {
      display: block;
      width: 100%;
      padding: 0.375rem 0.5rem;
      border: 1px solid #ccc;
      border-radius: 6px;
      background: #fff;
      cursor: pointer;
      font-size: 0.8125rem;
      margin-bottom: 0.375rem;
    }
    .md-editor-btn:hover { background: #f5f5f5; }
    .md-editor-btn-primary {
      background: #1a73e8;
      color: #fff;
      border-color: #1a73e8;
    }
    .md-editor-btn-primary:hover { background: #1557b0; }
    .md-editor-toml {
      margin-top: 0.375rem;
      padding: 0.5rem;
      background: #f5f5f5;
      border-radius: 4px;
      font-family: monospace;
      font-size: 0.6875rem;
      line-height: 1.4;
      white-space: pre-wrap;
      max-height: 180px;
      overflow-y: auto;
      color: #333;
    }
    """
end

# ─────────────────────────────────────────────────────────────────────────────
# Editor panel JavaScript
# ─────────────────────────────────────────────────────────────────────────────

"""Generate the editor panel JavaScript (served as /__editor__.js)."""
function _editor_panel_js(theme::ThemeConfig)::String
    # Pre-compute initial color tokens via the real HCT engine
    light, _ = hex_scheme_pair(theme.seed;
        secondary = theme.secondary_seed,
        tertiary = theme.tertiary_seed)
    initial_tokens_js = _scheme_to_js_object(light)

    sec_seed = something(theme.secondary_seed, theme.seed)
    ter_seed = something(theme.tertiary_seed, theme.seed)

    """
    (function() {
      'use strict';
      var STORAGE_KEY = '__md_editor_state__';
      // Snapshot of the tokens we last wrote, replayed by the head script on
      // the next page so the edited theme survives navigation without a flash
      var CSS_KEY = '__md_editor_css__';
      var root = document.documentElement;

      // Record every --md-sys-* property currently set inline on <html>
      function cacheCSS() {
        try {
          var vars = {}, s = root.style;
          for (var i = 0; i < s.length; i++) {
            var n = s[i];
            if (n.indexOf('--md-sys-') === 0) vars[n] = s.getPropertyValue(n);
          }
          sessionStorage.setItem(CSS_KEY, JSON.stringify({
            mode: isDarkFromDOM() ? 'dark' : 'light',
            vars: vars
          }));
        } catch(e) {}
      }

      // ── Panel toggle (persisted across page navigation) ──
      var panel = document.getElementById('md-editor-panel');
      var PANEL_KEY = '__md_editor_open__';
      // Restore panel state from sessionStorage
      try { if (sessionStorage.getItem(PANEL_KEY) === '1') panel.classList.remove('md-editor-collapsed'); } catch(e) {}
      document.getElementById('md-editor-toggle').addEventListener('click', function() {
        panel.classList.toggle('md-editor-collapsed');
        try { sessionStorage.setItem(PANEL_KEY, panel.classList.contains('md-editor-collapsed') ? '0' : '1'); } catch(e) {}
      });
      document.getElementById('md-editor-close').addEventListener('click', function() {
        panel.classList.add('md-editor-collapsed');
        try { sessionStorage.setItem(PANEL_KEY, '0'); } catch(e) {}
      });

      // ── Detect current dark mode from DOM ──
      // The built-in theme toggle (materialdocs.js) sets data-theme and
      // stores in localStorage. We read from the DOM to stay in sync.
      function isDarkFromDOM() {
        var attr = root.getAttribute('data-theme');
        if (attr === 'dark') return true;
        if (attr === 'light') return false;
        return window.matchMedia('(prefers-color-scheme: dark)').matches;
      }

      // ── Default state (from theme) ──
      // Override values are empty string = auto (derived from seed)
      var defaults = {
        seed: '$(theme.seed)',
        bgOverride: '',
        textOverride: '',
        secondaryOverride: '',
        tertiaryOverride: '',
        displayFont: '$(theme.display_font)',
        bodyFont: '$(theme.body_font)',
        codeFont: '$(theme.code_font)',
        cornerRadius: '$(theme.corner_radius)'
      };

      // ── State: restore from sessionStorage or use defaults ──
      // Note: darkMode is NOT stored — always derived from the DOM
      var state;
      try {
        var saved = sessionStorage.getItem(STORAGE_KEY);
        state = saved ? JSON.parse(saved) : Object.assign({}, defaults);
      } catch(e) {
        state = Object.assign({}, defaults);
      }
      // Remove legacy darkMode from state if present
      delete state.darkMode;
      // Migrate legacy secondary/tertiary keys to override keys
      if (state.secondary && !state.secondaryOverride) { state.secondaryOverride = state.secondary; }
      if (state.tertiary && !state.tertiaryOverride) { state.tertiaryOverride = state.tertiary; }
      delete state.secondary; delete state.tertiary;

      function saveState() {
        try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch(e) {}
      }

      // ── Google Fonts dynamic loader ──
      function loadGoogleFont(fontName) {
        var encoded = fontName.replace(/ /g, '+');
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://fonts.googleapis.com/css2?family=' + encoded + ':wght@400;500;600;700&display=swap';
        document.head.appendChild(link);
        // Actively trigger font loading so the browser renders it
        if (document.fonts && document.fonts.load) {
          document.fonts.load('1em "' + fontName + '"').then(function() {
            applyFonts();
          }).catch(function() {});
        }
      }

      // ── Seed color picker ──
      var seedPicker = document.getElementById('ed-seed');
      var seedHex = document.getElementById('ed-seed-hex');
      seedPicker.value = state.seed;
      seedHex.value = state.seed;
      seedPicker.addEventListener('input', function() {
        seedHex.value = seedPicker.value;
        state.seed = seedPicker.value;
        saveState();
        applyColors();
      });
      seedHex.addEventListener('change', function() {
        if (/^#[0-9a-fA-F]{6}/.test(seedHex.value)) {
          seedPicker.value = seedHex.value;
          state.seed = seedHex.value;
          saveState();
          applyColors();
        }
      });

      // ── Override pickers (bg, text, secondary, tertiary) ──
      // Empty hex field = auto (derived from seed)
      function bindOverride(id, stateKey) {
        var picker = document.getElementById('ed-' + id);
        var hex = document.getElementById('ed-' + id + '-hex');
        hex.value = state[stateKey] || '';
        if (state[stateKey]) picker.value = state[stateKey];
        picker.addEventListener('input', function() {
          hex.value = picker.value;
          state[stateKey] = picker.value;
          saveState();
          applyColors();
        });
        hex.addEventListener('change', function() {
          if (hex.value === '') {
            state[stateKey] = '';
            saveState();
            applyColors();
          } else if (/^#[0-9a-fA-F]{6}/.test(hex.value)) {
            picker.value = hex.value;
            state[stateKey] = hex.value;
            saveState();
            applyColors();
          }
        });
      }
      bindOverride('bg', 'bgOverride');
      bindOverride('text', 'textOverride');
      bindOverride('secondary', 'secondaryOverride');
      bindOverride('tertiary', 'tertiaryOverride');

      // ── Fonts ──
      ['display', 'body', 'code'].forEach(function(cat) {
        var key = cat + 'Font';
        var sel = document.getElementById('ed-' + cat + '-font');
        sel.value = state[key];
        sel.addEventListener('change', function(e) {
          state[key] = e.target.value;
          loadGoogleFont(e.target.value);
          saveState();
          applyFonts();
          updateTOML();
        });
      });

      // ── Shape ──
      var cornerSel = document.getElementById('ed-corner-radius');
      cornerSel.value = state.cornerRadius;
      cornerSel.addEventListener('change', function(e) {
        state.cornerRadius = e.target.value;
        saveState();
        applyShape();
        updateTOML();
      });

      // ── Dark mode (editor button) ──
      var darkBtn = document.getElementById('ed-toggle-dark');
      function syncDarkBtn() {
        darkBtn.textContent = isDarkFromDOM() ? '☀️ Toggle Light' : '🌙 Toggle Dark';
      }
      syncDarkBtn();
      darkBtn.addEventListener('click', function() {
        var nowDark = !isDarkFromDOM();
        root.setAttribute('data-theme', nowDark ? 'dark' : 'light');
        // Also update localStorage so the built-in toggle stays in sync
        try { localStorage.setItem('md-theme', nowDark ? 'dark' : 'light'); } catch(e) {}
        syncDarkBtn();
        applyColors();
      });

      // ── Watch for dark mode changes from the built-in navbar toggle ──
      var observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
          if (m.attributeName === 'data-theme') {
            syncDarkBtn();
            applyColors();
          }
        });
      });
      observer.observe(root, { attributes: true, attributeFilter: ['data-theme'] });

      // ── Export ──
      document.getElementById('ed-copy-toml').addEventListener('click', function() {
        var toml = generateTOML();
        navigator.clipboard.writeText(toml).then(function() {
          var btn = document.getElementById('ed-copy-toml');
          btn.textContent = '✅ Copied!';
          setTimeout(function() { btn.textContent = '📋 Copy TOML'; }, 1500);
        });
      });

      // ── HCT Color Engine ──
      // Faithful port of Google's material-color-utilities HCT solver.
      // Matches the Julia-side implementation in src/color/*.jl exactly.

      // sRGB ↔ XYZ matrices (D65, [0,100] scale)
      var S2X = [[0.41233895,0.35762064,0.18051042],[0.21265174,0.71515870,0.07218957],[0.01933080,0.11919552,0.95056300]];
      var X2S = [[3.2413774792388685,-1.5376652402851851,-0.49885366846268053],[-0.9691452513005321,1.8758853451067872,0.04156585616912061],[0.05562093689691305,-0.20395524564742123,1.0571799993703593]];
      // CAM16 M16 matrix
      var M16 = [[0.401288,0.650173,-0.051461],[-0.250268,1.204414,0.045854],[-0.002079,0.048952,0.953127]];
      var M16I = [[1.86206786,-1.01125463,0.14918677],[0.38752654,0.62144744,-0.00897398],[-0.01584150,-0.03412294,1.04996444]];
      var WP = [95.047,100.0,108.883];
      var YCOEFF = [0.2126,0.7152,0.0722];
      // Combined matrices for solver
      var SD_FROM_LIN = [[0.001200833568784504,0.002389694492170889,0.0002795742885861124],[0.0005891086651375999,0.0029785502573438758,0.0003270666104008398],[0.00010146692491640572,0.0005364214359186694,0.0032979401770712076]];
      var LIN_FROM_SD = [[1373.2198709594231,-1100.4251190754821,-7.278681089101213],[-271.815969077903,559.6580465940733,-32.46047482791194],[1.9622899599665666,-57.173814538844006,308.7233197812385]];

      // Critical planes for gamut binary search
      var CRIT = [];
      for (var ci = 0; ci < 256; ci++) {
        var cn = (ci + 0.5) / 255.0;
        CRIT[ci] = cn <= 0.040449936 ? cn / 12.92 * 100.0 : Math.pow((cn + 0.055) / 1.055, 2.4) * 100.0;
      }

      function linearize(v) { var n = v / 255.0; return n <= 0.040449936 ? n / 12.92 * 100.0 : Math.pow((n + 0.055) / 1.055, 2.4) * 100.0; }
      function delinearize(c) { var n = c / 100.0; var d = n <= 0.0031308 ? n * 12.92 : 1.055 * Math.pow(n, 1.0/2.4) - 0.055; return Math.max(0, Math.min(255, Math.round(d * 255.0))); }
      function trueDelinearize(c) { var n = c / 100.0; return (n <= 0.0031308 ? n * 12.92 : 1.055 * Math.pow(n, 1.0/2.4) - 0.055) * 255.0; }
      function lstarFromY(y) { var n = y / 100.0; return n <= 216.0/24389.0 ? n * (24389.0/27.0) : 116.0 * Math.cbrt(n) - 16.0; }
      function yFromLstar(l) { return l > 8.0 ? Math.pow((l + 16.0) / 116.0, 3) * 100.0 : l / (24389.0/27.0) * 100.0; }

      function srgbFromTone(tone) { var y = yFromLstar(tone); var c = delinearize(y); return [c,c,c]; }

      function toneFromRGB(r,g,b) {
        var y = YCOEFF[0]*linearize(r) + YCOEFF[1]*linearize(g) + YCOEFF[2]*linearize(b);
        return lstarFromY(y);
      }

      // Precompute default viewing conditions (matches Julia DEFAULT_VC)
      var VC = (function() {
        var la = (200.0/Math.PI) * yFromLstar(50.0) / 100.0;
        var rW = M16[0][0]*WP[0] + M16[0][1]*WP[1] + M16[0][2]*WP[2];
        var gW = M16[1][0]*WP[0] + M16[1][1]*WP[1] + M16[1][2]*WP[2];
        var bW = M16[2][0]*WP[0] + M16[2][1]*WP[1] + M16[2][2]*WP[2];
        var f = 0.8 + 2.0/10.0;
        var c = f >= 0.9 ? 0.59 + (0.69-0.59)*(f-0.9)*10.0 : 0.525 + (0.59-0.525)*(f-0.8)*10.0;
        var nc = f;
        var d = Math.max(0, Math.min(1, f * (1.0 - (1.0/3.6) * Math.exp((-la - 42.0)/92.0))));
        var rgbD = [d*(100.0/rW)+1.0-d, d*(100.0/gW)+1.0-d, d*(100.0/bW)+1.0-d];
        var k = 1.0/(5.0*la+1.0), k4 = k*k*k*k, k4f = 1.0-k4;
        var fl = k4*la + 0.1*k4f*k4f*Math.cbrt(5.0*la);
        var n = yFromLstar(50.0)/WP[1];
        var z = 1.48 + Math.sqrt(n);
        var nbb = 0.725/Math.pow(n,0.2);
        var rWa = rgbD[0]*rW, gWa = rgbD[1]*gW, bWa = rgbD[2]*bW;
        var rWf = Math.pow(fl*Math.abs(rWa)/100.0,0.42);
        var gWf = Math.pow(fl*Math.abs(gWa)/100.0,0.42);
        var bWf = Math.pow(fl*Math.abs(bWa)/100.0,0.42);
        var rWA = Math.sign(rWa)*400.0*rWf/(rWf+27.13);
        var gWA = Math.sign(gWa)*400.0*gWf/(gWf+27.13);
        var bWA = Math.sign(bWa)*400.0*bWf/(bWf+27.13);
        var aw = (2.0*rWA+gWA+0.05*bWA-0.305)*nbb;
        return {n:n, aw:aw, nbb:nbb, ncb:nbb, c:c, nc:nc, fl:fl, flRoot:Math.pow(fl,0.25), z:z, rgbD:rgbD};
      })();

      function cam16FromRGB(r,g,b) {
        var rl=linearize(r), gl=linearize(g), bl=linearize(b);
        var x=S2X[0][0]*rl+S2X[0][1]*gl+S2X[0][2]*bl;
        var y=S2X[1][0]*rl+S2X[1][1]*gl+S2X[1][2]*bl;
        var zz=S2X[2][0]*rl+S2X[2][1]*gl+S2X[2][2]*bl;
        var rC=M16[0][0]*x+M16[0][1]*y+M16[0][2]*zz;
        var gC=M16[1][0]*x+M16[1][1]*y+M16[1][2]*zz;
        var bC=M16[2][0]*x+M16[2][1]*y+M16[2][2]*zz;
        var rD=VC.rgbD[0]*rC, gD=VC.rgbD[1]*gC, bD=VC.rgbD[2]*bC;
        var rAF=Math.pow(VC.fl*Math.abs(rD)/100.0,0.42);
        var gAF=Math.pow(VC.fl*Math.abs(gD)/100.0,0.42);
        var bAF=Math.pow(VC.fl*Math.abs(bD)/100.0,0.42);
        var rA=Math.sign(rD)*400.0*rAF/(rAF+27.13);
        var gA=Math.sign(gD)*400.0*gAF/(gAF+27.13);
        var bA=Math.sign(bD)*400.0*bAF/(bAF+27.13);
        var a=(11.0*rA-12.0*gA+bA)/11.0;
        var bo=(rA+gA-2.0*bA)/9.0;
        var hRad=Math.atan2(bo,a);
        var hDeg=hRad*180.0/Math.PI;
        if(hDeg<0)hDeg+=360.0; if(hDeg>=360.0)hDeg-=360.0;
        var u=(20.0*rA+20.0*gA+21.0*bA)/20.0;
        var p2=(40.0*rA+20.0*gA+bA)/20.0;
        var ac=p2*VC.nbb;
        var j=100.0*Math.pow(ac/VC.aw,VC.c*VC.z);
        var hP=hDeg<20.14?hDeg+360.0:hDeg;
        var eH=0.25*(Math.cos(hP*Math.PI/180.0+2.0)+3.8);
        var p1=50000.0/13.0*eH*VC.nc*VC.ncb;
        var t=p1*Math.sqrt(a*a+bo*bo)/(u+0.305);
        var alpha=Math.pow(t,0.9)*Math.pow(1.64-Math.pow(0.29,VC.n),0.73);
        var cVal=alpha*Math.sqrt(j/100.0);
        return {hue:hDeg, chroma:cVal, j:j};
      }

      function hexToHCT(hex) {
        var r=parseInt(hex.slice(1,3),16), g=parseInt(hex.slice(3,5),16), b=parseInt(hex.slice(5,7),16);
        var cam=cam16FromRGB(r,g,b);
        return {hue:cam.hue, chroma:cam.chroma, tone:toneFromRGB(r,g,b)};
      }

      // HCT solver: find sRGB for (hue, chroma, tone)
      function sanitizeDeg(d) { d = d % 360.0; return d < 0 ? d + 360.0 : d; }
      function chromAdapt(c) { var af=Math.pow(Math.abs(c),0.42); return Math.sign(c)*400.0*af/(af+27.13); }
      function invChromAdapt(a) { var aa=Math.abs(a); var base=Math.max(0,27.13*aa/(400.0-aa)); return Math.sign(a)*Math.pow(base,1.0/0.42); }

      function hueOf(lr,lg,lb) {
        var s0=SD_FROM_LIN[0][0]*lr+SD_FROM_LIN[0][1]*lg+SD_FROM_LIN[0][2]*lb;
        var s1=SD_FROM_LIN[1][0]*lr+SD_FROM_LIN[1][1]*lg+SD_FROM_LIN[1][2]*lb;
        var s2=SD_FROM_LIN[2][0]*lr+SD_FROM_LIN[2][1]*lg+SD_FROM_LIN[2][2]*lb;
        return Math.atan2((chromAdapt(s0)+chromAdapt(s1)-2.0*chromAdapt(s2))/9.0,
                          (11.0*chromAdapt(s0)-12.0*chromAdapt(s1)+chromAdapt(s2))/11.0);
      }

      function cyclic(a,b,c) { var dab=sanitizeDeg(b-a), dac=sanitizeDeg(c-a); return dab<dac; }

      function nthVertex(y,n) {
        var kR=YCOEFF[0],kG=YCOEFF[1],kB=YCOEFF[2];
        var ca=(n%4<=1)?0:100, cb=(n%2===0)?0:100;
        if(n<4){var r=(y-ca*kG-cb*kB)/kR; return(r>=0&&r<=100)?[r,ca,cb]:null;}
        if(n<8){var g=(y-cb*kR-ca*kB)/kG; return(g>=0&&g<=100)?[cb,g,ca]:null;}
        var bv=(y-ca*kR-cb*kG)/kB; return(bv>=0&&bv<=100)?[ca,cb,bv]:null;
      }

      function setCoord(src,coord,tgt,ax) {
        var t=(coord-src[ax])/(tgt[ax]-src[ax]);
        return [src[0]+(tgt[0]-src[0])*t, src[1]+(tgt[1]-src[1])*t, src[2]+(tgt[2]-src[2])*t];
      }

      function bisectToLimit(y,targetHue) {
        var left=null, right=null, lh=0, rh=0, init=false, uncut=true;
        for(var n=0;n<12;n++){
          var mid=nthVertex(y,n); if(!mid)continue;
          var mh=hueOf(mid[0],mid[1],mid[2]);
          if(!init){left=mid;right=mid;lh=mh;rh=mh;init=true;continue;}
          if(uncut||cyclic(lh*180/Math.PI,mh*180/Math.PI,rh*180/Math.PI)){
            uncut=false;
            if(cyclic(lh*180/Math.PI,targetHue*180/Math.PI,mh*180/Math.PI)){right=mid;rh=mh;}
            else{left=mid;lh=mh;}
          }
        }
        for(var ax=0;ax<3;ax++){
          if(left[ax]===right[ax])continue;
          var lp,rp;
          if(left[ax]<right[ax]){lp=Math.floor(trueDelinearize(left[ax])-0.5);rp=Math.ceil(trueDelinearize(right[ax])-0.5);}
          else{lp=Math.ceil(trueDelinearize(left[ax])-0.5);rp=Math.floor(trueDelinearize(right[ax])-0.5);}
          for(var i=0;i<8;i++){
            if(Math.abs(rp-lp)<=1)break;
            var mp=Math.floor((lp+rp)/2);
            var mc=CRIT[Math.max(0,Math.min(255,mp))];
            var m=setCoord(left,mc,right,ax);
            var mhh=hueOf(m[0],m[1],m[2]);
            if(cyclic(lh*180/Math.PI,targetHue*180/Math.PI,mhh*180/Math.PI)){right=m;rp=mp;}
            else{left=m;lh=mhh;lp=mp;}
          }
        }
        return [(left[0]+right[0])/2,(left[1]+right[1])/2,(left[2]+right[2])/2];
      }

      function findByJ(hRad,chroma,y) {
        var j=Math.sqrt(y)*11.0;
        var tic=1.0/Math.pow(1.64-Math.pow(0.29,VC.n),0.73);
        var eH=0.25*(Math.cos(hRad+2.0)+3.8);
        var p1=eH*(50000.0/13.0)*VC.nc*VC.ncb;
        var hS=Math.sin(hRad), hC=Math.cos(hRad);
        for(var it=0;it<5;it++){
          var jn=j/100.0;
          var alpha=(chroma===0||j===0)?0:chroma/Math.sqrt(jn);
          var t=Math.pow(alpha*tic,1.0/0.9);
          var ac=VC.aw*Math.pow(jn,1.0/(VC.c*VC.z));
          var p2=ac/VC.nbb;
          var gamma=23.0*(p2+0.305)*t/(23.0*p1+11.0*t*hC+108.0*t*hS);
          var a=gamma*hC, b=gamma*hS;
          var rA=(460.0*p2+451.0*a+288.0*b)/1403.0;
          var gA=(460.0*p2-891.0*a-261.0*b)/1403.0;
          var bA=(460.0*p2-220.0*a-6300.0*b)/1403.0;
          var rS=invChromAdapt(rA), gS=invChromAdapt(gA), bS=invChromAdapt(bA);
          var lr=LIN_FROM_SD[0][0]*rS+LIN_FROM_SD[0][1]*gS+LIN_FROM_SD[0][2]*bS;
          var lg=LIN_FROM_SD[1][0]*rS+LIN_FROM_SD[1][1]*gS+LIN_FROM_SD[1][2]*bS;
          var lb=LIN_FROM_SD[2][0]*rS+LIN_FROM_SD[2][1]*gS+LIN_FROM_SD[2][2]*bS;
          if(lr<0||lg<0||lb<0)return null;
          var fnj=YCOEFF[0]*lr+YCOEFF[1]*lg+YCOEFF[2]*lb;
          if(fnj<=0)return null;
          if(it===4||Math.abs(fnj-y)<0.002){
            if(lr>100.01||lg>100.01||lb>100.01)return null;
            return [delinearize(lr),delinearize(lg),delinearize(lb)];
          }
          j=j-(fnj-y)*j/(2.0*fnj);
        }
        return null;
      }

      function solveHCT(hue,chroma,tone) {
        if(chroma<1||tone<1||tone>99) return srgbFromTone(tone);
        var hDeg=sanitizeDeg(hue);
        var hRad=hDeg/180.0*Math.PI;
        var y=yFromLstar(tone);
        var exact=findByJ(hRad,chroma,y);
        if(exact)return exact;
        var lin=bisectToLimit(y,hRad);
        return [delinearize(lin[0]),delinearize(lin[1]),delinearize(lin[2])];
      }

      function rgbToHex(r,g,b) {
        var h=function(v){var s=v.toString(16);return s.length===1?'0'+s:s;};
        return '#'+h(r)+h(g)+h(b);
      }

      // TonalPalette: hue + chroma → hex at any tone
      function tonalPalette(hue,chroma) {
        var cache = {};
        return function(tone) {
          if(cache[tone]!==undefined)return cache[tone];
          var rgb=solveHCT(hue,chroma,tone);
          var hex=rgbToHex(rgb[0],rgb[1],rgb[2]);
          cache[tone]=hex;
          return hex;
        };
      }

      // MD3 palette derivation constants (match color_scheme.jl)
      var SEC_CHROMA = 16.0;
      var TER_HUE_OFFSET = 60.0;
      var TER_CHROMA = 24.0;
      var NEUTRAL_CHROMA = 4.0;
      var NV_CHROMA = 8.0;
      var ERR_HUE = 25.0;
      var ERR_CHROMA = 84.0;

      function generateScheme(isDark) {
        var seed = hexToHCT(state.seed);
        var seedHue = seed.hue;

        // Derive secondary/tertiary from seed unless overridden
        var secHCT = state.secondaryOverride ? hexToHCT(state.secondaryOverride) : null;
        var terHCT = state.tertiaryOverride ? hexToHCT(state.tertiaryOverride) : null;

        // Build tonal palettes (matches color_scheme.jl exactly)
        var P  = tonalPalette(seedHue, seed.chroma);
        var S  = secHCT ? tonalPalette(secHCT.hue, secHCT.chroma) : tonalPalette(seedHue, SEC_CHROMA);
        var T  = terHCT ? tonalPalette(terHCT.hue, terHCT.chroma) : tonalPalette(sanitizeDeg(seedHue + TER_HUE_OFFSET), TER_CHROMA);
        var N  = tonalPalette(seedHue, NEUTRAL_CHROMA);
        var NV = tonalPalette(seedHue, NV_CHROMA);
        var E  = tonalPalette(ERR_HUE, ERR_CHROMA);

        // Role mapping: [palette, lightTone, darkTone]
        var roles = {
          'primary':              [P,  40, 80],  'on-primary':              [P, 100, 20],
          'primary-container':    [P,  90, 30],  'on-primary-container':    [P,  10, 90],
          'secondary':            [S,  40, 80],  'on-secondary':            [S, 100, 20],
          'secondary-container':  [S,  90, 30],  'on-secondary-container':  [S,  10, 90],
          'tertiary':             [T,  40, 80],  'on-tertiary':             [T, 100, 20],
          'tertiary-container':   [T,  90, 30],  'on-tertiary-container':   [T,  10, 90],
          'error':                [E,  40, 80],  'on-error':                [E, 100, 20],
          'error-container':      [E,  90, 30],  'on-error-container':      [E,  10, 90],
          'surface':              [N,  98,  6],  'on-surface':              [N,  10, 90],
          'surface-container':    [N,  94, 12],  'surface-container-high':  [N,  92, 17],
          'surface-container-highest': [N, 90, 22], 'surface-container-low': [N, 96, 10],
          'surface-container-lowest':  [N, 100, 4],
          'on-surface-variant':   [NV, 30, 80],  'outline':                [NV, 50, 60],
          'outline-variant':      [NV, 80, 30],
          'inverse-surface':      [N,  20, 90],  'inverse-on-surface':     [N,  95, 20],
          'inverse-primary':      [P,  80, 40]
        };

        var scheme = {};
        for (var role in roles) {
          var r = roles[role];
          scheme[role] = r[0](isDark ? r[2] : r[1]);
        }

        // Apply overrides
        if (state.bgOverride) scheme['surface'] = state.bgOverride;
        if (state.textOverride) scheme['on-surface'] = state.textOverride;

        return scheme;
      }

      // ── Palette preview ──
      function updatePalette() {
        var scheme = generateScheme(isDarkFromDOM());
        var roles = [
          ['primary', 'Primary'],
          ['on-primary', 'On Primary'],
          ['primary-container', 'Container'],
          ['on-primary-container', 'On Container'],
          ['secondary', 'Secondary'],
          ['on-secondary', 'On Secondary'],
          ['secondary-container', 'Sec Container'],
          ['on-secondary-container', 'On Sec Cont'],
          ['tertiary', 'Tertiary'],
          ['on-tertiary', 'On Tertiary'],
          ['tertiary-container', 'Ter Container'],
          ['on-tertiary-container', 'On Ter Cont'],
          ['surface', 'Background'],
          ['on-surface', 'Text'],
          ['surface-container', 'Surface'],
          ['outline', 'Outline']
        ];
        var html = '';
        for (var i = 0; i < roles.length; i++) {
          html += '<div class="md-editor-swatch" title="' + roles[i][1] + '" style="background:' + scheme[roles[i][0]] + '"></div>';
        }
        var el = document.getElementById('ed-palette');
        if (el) el.innerHTML = html;
      }

      // ── Apply changes to the live page ──
      // applyColors reads dark mode from the DOM, not from state
      function applyColors() {
        var scheme = generateScheme(isDarkFromDOM());
        for (var key in scheme) {
          root.style.setProperty('--md-sys-color-' + key, scheme[key]);
        }
        updatePalette();
        updateTOML();
        cacheCSS();
      }

      function applyFonts() {
        var displayStack = "'" + state.displayFont + "', system-ui, sans-serif";
        var bodyStack = "'" + state.bodyFont + "', system-ui, sans-serif";
        var codeStack = "'" + state.codeFont + "', 'Menlo', monospace";
        // Update all typescale font tokens
        var cats = ['display-large','display-medium','display-small',
                    'headline-large','headline-medium','headline-small'];
        cats.forEach(function(c) { root.style.setProperty('--md-sys-typescale-'+c+'-font', displayStack); });
        var bodyCats = ['title-large','title-medium','title-small',
                        'body-large','body-medium','body-small',
                        'label-large','label-medium','label-small'];
        bodyCats.forEach(function(c) { root.style.setProperty('--md-sys-typescale-'+c+'-font', bodyStack); });
        root.style.setProperty('--md-sys-typescale-body-large-code-font', codeStack);
        cacheCSS();
      }

      function applyShape() {
        var radii = {
          sharp:   [0, 2, 4, 8, 12, 16],
          'default': [4, 8, 12, 16, 28, 9999],
          rounded: [8, 12, 20, 28, 36, 9999],
          pill:    [12, 16, 28, 36, 44, 9999]
        };
        var names = ['extra-small','small','medium','large','extra-large','full'];
        var r = radii[state.cornerRadius] || radii['default'];
        names.forEach(function(n, i) {
          root.style.setProperty('--md-sys-shape-corner-' + n, r[i] + 'px');
        });
        cacheCSS();
      }

      function applyAll() {
        applyColors();
        // Load any non-default fonts
        loadGoogleFont(state.displayFont);
        loadGoogleFont(state.bodyFont);
        loadGoogleFont(state.codeFont);
        applyFonts();
        applyShape();
        updateTOML();
      }

      function generateTOML() {
        var lines = [
          '# .materialdocs.toml',
          '# Generated by MaterialDocs.editor() — edit freely',
          '# Save as docs/.materialdocs.toml — it will be auto-detected by Material3()',
          '',
          '[theme]',
          'name = "custom"',
          'seed = "' + state.seed + '"',
        ];
        if (state.secondaryOverride) lines.push('secondary_seed = "' + state.secondaryOverride + '"');
        if (state.tertiaryOverride) lines.push('tertiary_seed = "' + state.tertiaryOverride + '"');
        lines.push('');
        lines.push('[theme.fonts]');
        lines.push('display = "' + state.displayFont + '"');
        lines.push('body = "' + state.bodyFont + '"');
        lines.push('code = "' + state.codeFont + '"');
        lines.push('');
        lines.push('[theme.shape]');
        lines.push('corner_radius = "' + state.cornerRadius + '"');
        if (state.bgOverride || state.textOverride) {
          lines.push('');
          lines.push('[theme.custom_colors]');
          if (state.bgOverride) lines.push('surface = "' + state.bgOverride + '"');
          if (state.textOverride) lines.push('on_surface = "' + state.textOverride + '"');
        }
        return lines.join('\\n') + '\\n';
      }

      function updateTOML() {
        var pre = document.getElementById('ed-toml-preview');
        if (pre) pre.textContent = generateTOML();
      }

      // Check if state differs from defaults (i.e., user has made changes)
      var stateChanged = JSON.stringify(state) !== JSON.stringify(defaults);

      // Apply saved state on page load (re-applies after navigation)
      if (stateChanged) {
        applyAll();
      } else {
        // Back to the built-in theme: drop the cache so the head script on the
        // next page doesn't replay stale overrides
        try { sessionStorage.removeItem(CSS_KEY); } catch(e) {}
        updatePalette();
        updateTOML();
      }
    })();
    """
end

"""Convert a Julia color scheme dict to a JS object literal."""
function _scheme_to_js_object(scheme::Dict{Symbol,String})::String
    io = IOBuffer()
    print(io, '{')
    is_first = true
    for (role, hex) in sort(collect(scheme); by=Base.first)
        !is_first && print(io, ',')
        is_first = false
        css_name = replace(string(role), '_' => '-')
        print(io, "\"", css_name, "\":\"", hex, "\"")
    end
    print(io, '}')
    String(take!(io))
end
