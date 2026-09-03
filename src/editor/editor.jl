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
            @async _handle_request(sock, build_abs, panel_html, panel_js, theme)
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
                         panel_html::String, panel_js::String,
                         theme::ThemeConfig)
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

        # Special route: the colour scheme, generated by the same Julia code
        # the build uses. The panel has no colour engine of its own.
        if path == "/__scheme__"
            raw_query = occursin('?', raw_path) ? split(raw_path, '?'; limit=2)[2] : ""
            try
                _send_response(sock, 200, "application/json", _scheme_json(raw_query, theme))
            catch e
                e isa ArgumentError || rethrow(e)
                _send_response(sock, 400, "text/plain", "Bad scheme request: $(e.msg)")
            end
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

"""URL-encode a string for use in a query value."""
function _url_encode(s::AbstractString)::String
    io = IOBuffer()
    for b in codeunits(String(s))
        c = Char(b)
        if isletter(c) || isdigit(c) || c in ('-', '_', '.', '~')
            print(io, c)
        else
            print(io, '%', uppercase(string(b, base=16, pad=2)))
        end
    end
    String(take!(io))
end

"""Parse a URL query string into a Dict of decoded key/value pairs."""
function _parse_query(query::AbstractString)::Dict{String,String}
    out = Dict{String,String}()
    isempty(query) && return out
    for pair in split(query, '&')
        isempty(pair) && continue
        k, _, v = partition_kv(pair)
        out[_url_decode(k)] = _url_decode(v)
    end
    out
end

"""Split `key=value`, tolerating a missing `=`."""
function partition_kv(pair::AbstractString)
    i = findfirst('=', pair)
    i === nothing ? (pair, "", "") : (pair[1:prevind(pair, i)], "=", pair[nextind(pair, i):end])
end

"""
    _scheme_json(query, theme) -> String

Generate the colour scheme the *build* would produce, as JSON, from the
editor panel's query parameters. This is the single source of truth: the panel
renders whatever this returns, so the preview cannot drift from the output.

Throws `ArgumentError` for a malformed seed rather than rendering something
subtly wrong.
"""
function _scheme_json(query::AbstractString, theme::ThemeConfig)::String
    p = _parse_query(query)
    seed = get(p, "seed", theme.seed)
    dark = get(p, "dark", "false") == "true"
    sec = get(p, "secondary", "")
    ter = get(p, "tertiary", "")

    _validate_hex(seed, "seed", "editor request")
    isempty(sec) || _validate_hex(sec, "secondary", "editor request")
    isempty(ter) || _validate_hex(ter, "tertiary", "editor request")

    scheme = hex_scheme(seed;
        dark = dark,
        secondary = isempty(sec) ? nothing : sec,
        tertiary = isempty(ter) ? nothing : ter,
    )
    _scheme_to_js_object(scheme)
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

      // ── Scheme generation ──
      // There is deliberately no colour engine here. The panel asks the Julia
      // server, which runs the same `hex_scheme` the build runs, so the preview
      // cannot drift from the generated site.
      var lastScheme = null;

      function schemeURL(isDark) {
        return '/__scheme__'
          + '?seed=' + encodeURIComponent(state.seed)
          + '&dark=' + (isDark ? 'true' : 'false')
          + '&secondary=' + encodeURIComponent(state.secondaryOverride || '')
          + '&tertiary=' + encodeURIComponent(state.tertiaryOverride || '');
      }

      function fetchScheme(isDark, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', schemeURL(isDark), true);
        xhr.onload = function() {
          if (xhr.status !== 200) return;
          var scheme;
          try { scheme = JSON.parse(xhr.responseText); } catch (e) { return; }
          // Surface and text overrides sit on top of the generated scheme.
          if (state.bgOverride) scheme['surface'] = state.bgOverride;
          if (state.textOverride) scheme['on-surface'] = state.textOverride;
          lastScheme = scheme;
          cb(scheme);
        };
        xhr.send();
      }

      // ── Palette preview ──
      var PREVIEW_ROLES = [
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

      function renderPalette(scheme) {
        var el = document.getElementById('ed-palette');
        if (!el) return;
        var html = '';
        for (var i = 0; i < PREVIEW_ROLES.length; i++) {
          var role = PREVIEW_ROLES[i];
          html += '<div class="md-editor-swatch" title="' + role[1] +
                  '" style="background:' + scheme[role[0]] + '"></div>';
        }
        el.innerHTML = html;
      }

      // Callable with a scheme already in hand, or with none — in which case
      // it fetches one.
      function updatePalette(scheme) {
        if (scheme) { renderPalette(scheme); return; }
        if (lastScheme) { renderPalette(lastScheme); return; }
        fetchScheme(isDarkFromDOM(), renderPalette);
      }

      // ── Apply changes to the live page ──
      // Dark mode is read from the DOM, not from state. The seed picker fires
      // continuously while dragging, so requests are coalesced to one a frame.
      var colorTimer = null;
      function applyColors() {
        if (colorTimer) clearTimeout(colorTimer);
        colorTimer = setTimeout(function() {
          colorTimer = null;
          fetchScheme(isDarkFromDOM(), function(scheme) {
            for (var key in scheme) {
              root.style.setProperty('--md-sys-color-' + key, scheme[key]);
            }
            renderPalette(scheme);
            updateTOML();
            cacheCSS();
          });
        }, 16);
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
