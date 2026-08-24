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
                  theme::ThemeConfig=resolve_theme(:default))
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
    # Inject panel before </body>, and load the editor JS
    injection = """
    $panel_html
    <script src="/__editor__.js"></script>
    """
    if contains(html, "</body>")
        replace(html, "</body>" => injection * "\n</body>")
    else
        html * injection
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
            <h4>Colors</h4>
            <div class="md-editor-field">
              <label>Seed</label>
              <div class="md-editor-color-row">
                <input type="color" id="ed-seed" value="$(theme.seed)">
                <input type="text" id="ed-seed-hex" value="$(theme.seed)" class="md-editor-hex">
              </div>
            </div>
            <div class="md-editor-field">
              <label>Secondary</label>
              <div class="md-editor-color-row">
                <input type="color" id="ed-secondary" value="$(sec_seed)">
                <input type="text" id="ed-secondary-hex" value="$(sec_seed)" class="md-editor-hex">
              </div>
            </div>
            <div class="md-editor-field">
              <label>Tertiary</label>
              <div class="md-editor-color-row">
                <input type="color" id="ed-tertiary" value="$(ter_seed)">
                <input type="text" id="ed-tertiary-hex" value="$(ter_seed)" class="md-editor-hex">
              </div>
            </div>
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
    light, _ = color_scheme_pair(theme.seed;
        secondary = theme.secondary_seed,
        tertiary = theme.tertiary_seed)
    initial_tokens_js = _scheme_to_js_object(light)

    sec_seed = something(theme.secondary_seed, theme.seed)
    ter_seed = something(theme.tertiary_seed, theme.seed)

    """
    (function() {
      'use strict';
      // ── Panel toggle ──
      var panel = document.getElementById('md-editor-panel');
      document.getElementById('md-editor-toggle').addEventListener('click', function() {
        panel.classList.toggle('md-editor-collapsed');
      });
      document.getElementById('md-editor-close').addEventListener('click', function() {
        panel.classList.add('md-editor-collapsed');
      });

      // ── State ──
      var state = {
        seed: '$(theme.seed)',
        secondary: '$sec_seed',
        tertiary: '$ter_seed',
        displayFont: '$(theme.display_font)',
        bodyFont: '$(theme.body_font)',
        codeFont: '$(theme.code_font)',
        cornerRadius: '$(theme.corner_radius)',
        darkMode: false
      };

      // ── Color pickers ──
      ['seed', 'secondary', 'tertiary'].forEach(function(name) {
        var picker = document.getElementById('ed-' + name);
        var hex = document.getElementById('ed-' + name + '-hex');
        picker.addEventListener('input', function() {
          hex.value = picker.value;
          state[name] = picker.value;
          applyTheme();
        });
        hex.addEventListener('change', function() {
          if (/^#[0-9a-fA-F]{6}/.test(hex.value)) {
            picker.value = hex.value;
            state[name] = hex.value;
            applyTheme();
          }
        });
      });

      // ── Fonts ──
      ['display', 'body', 'code'].forEach(function(cat) {
        var key = cat + 'Font';
        document.getElementById('ed-' + cat + '-font').addEventListener('change', function(e) {
          state[key] = e.target.value;
          applyFonts();
          updateTOML();
        });
      });

      // ── Shape ──
      document.getElementById('ed-corner-radius').addEventListener('change', function(e) {
        state.cornerRadius = e.target.value;
        applyShape();
        updateTOML();
      });

      // ── Dark mode ──
      document.getElementById('ed-toggle-dark').addEventListener('click', function() {
        state.darkMode = !state.darkMode;
        this.textContent = state.darkMode ? '☀️ Toggle Light' : '🌙 Toggle Dark';
        document.documentElement.setAttribute('data-theme', state.darkMode ? 'dark' : 'light');
        applyTheme();
      });

      // ── Export ──
      document.getElementById('ed-copy-toml').addEventListener('click', function() {
        var toml = generateTOML();
        navigator.clipboard.writeText(toml).then(function() {
          var btn = document.getElementById('ed-copy-toml');
          btn.textContent = '✅ Copied!';
          setTimeout(function() { btn.textContent = '📋 Copy TOML'; }, 1500);
        });
      });

      // ── HSL color engine (approximate preview) ──
      function hexToHSL(hex) {
        var r = parseInt(hex.slice(1,3), 16) / 255;
        var g = parseInt(hex.slice(3,5), 16) / 255;
        var b = parseInt(hex.slice(5,7), 16) / 255;
        var max = Math.max(r, g, b), min = Math.min(r, g, b);
        var h, s, l = (max + min) / 2;
        if (max === min) { h = s = 0; }
        else {
          var d = max - min;
          s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
          if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
          else if (max === g) h = ((b - r) / d + 2) / 6;
          else h = ((r - g) / d + 4) / 6;
        }
        return [h * 360, s * 100, l * 100];
      }

      function hslToHex(h, s, l) {
        h = ((h % 360) + 360) % 360;
        s = Math.max(0, Math.min(100, s)) / 100;
        l = Math.max(0, Math.min(100, l)) / 100;
        var c = (1 - Math.abs(2 * l - 1)) * s;
        var x = c * (1 - Math.abs((h / 60) % 2 - 1));
        var m = l - c / 2;
        var r, g, b;
        if (h < 60) { r = c; g = x; b = 0; }
        else if (h < 120) { r = x; g = c; b = 0; }
        else if (h < 180) { r = 0; g = c; b = x; }
        else if (h < 240) { r = 0; g = x; b = c; }
        else if (h < 300) { r = x; g = 0; b = c; }
        else { r = c; g = 0; b = x; }
        var toHex = function(v) {
          var hx = Math.round((v + m) * 255).toString(16);
          return hx.length === 1 ? '0' + hx : hx;
        };
        return '#' + toHex(r) + toHex(g) + toHex(b);
      }

      function makeRoles(h, s, isDark) {
        var roles = {};
        if (isDark) {
          roles.main = hslToHex(h, s * 0.8, 70);
          roles.on = hslToHex(h, s * 0.5, 15);
          roles.container = hslToHex(h, s * 0.7, 25);
          roles.onContainer = hslToHex(h, s * 0.6, 85);
        } else {
          roles.main = hslToHex(h, s * 0.8, 40);
          roles.on = '#ffffff';
          roles.container = hslToHex(h, s * 0.6, 90);
          roles.onContainer = hslToHex(h, s * 0.7, 15);
        }
        return roles;
      }

      function generateScheme(isDark) {
        var p = hexToHSL(state.seed), s = hexToHSL(state.secondary), t = hexToHSL(state.tertiary);
        var pri = makeRoles(p[0], p[1], isDark);
        var sec = makeRoles(s[0], s[1], isDark);
        var ter = makeRoles(t[0], t[1], isDark);
        var h = p[0], sat = p[1];
        var scheme = {
          'primary': pri.main, 'on-primary': pri.on,
          'primary-container': pri.container, 'on-primary-container': pri.onContainer,
          'secondary': sec.main, 'on-secondary': sec.on,
          'secondary-container': sec.container, 'on-secondary-container': sec.onContainer,
          'tertiary': ter.main, 'on-tertiary': ter.on,
          'tertiary-container': ter.container, 'on-tertiary-container': ter.onContainer,
        };
        if (isDark) {
          scheme['surface'] = hslToHex(h, sat * 0.15, 10);
          scheme['on-surface'] = hslToHex(h, sat * 0.08, 90);
          scheme['surface-container'] = hslToHex(h, sat * 0.12, 15);
          scheme['surface-container-high'] = hslToHex(h, sat * 0.1, 20);
          scheme['surface-container-highest'] = hslToHex(h, sat * 0.08, 25);
          scheme['surface-container-low'] = hslToHex(h, sat * 0.12, 12);
          scheme['surface-container-lowest'] = hslToHex(h, sat * 0.1, 6);
          scheme['on-surface-variant'] = hslToHex(h, sat * 0.1, 70);
          scheme['outline'] = hslToHex(h, sat * 0.15, 50);
          scheme['outline-variant'] = hslToHex(h, sat * 0.1, 30);
          scheme['error'] = '#ffb4ab'; scheme['on-error'] = '#690005';
          scheme['error-container'] = '#93000a'; scheme['on-error-container'] = '#ffdad6';
        } else {
          scheme['surface'] = hslToHex(h, sat * 0.05, 98);
          scheme['on-surface'] = hslToHex(h, sat * 0.08, 12);
          scheme['surface-container'] = hslToHex(h, sat * 0.08, 94);
          scheme['surface-container-high'] = hslToHex(h, sat * 0.06, 91);
          scheme['surface-container-highest'] = hslToHex(h, sat * 0.05, 88);
          scheme['surface-container-low'] = hslToHex(h, sat * 0.06, 96);
          scheme['surface-container-lowest'] = '#ffffff';
          scheme['on-surface-variant'] = hslToHex(h, sat * 0.1, 35);
          scheme['outline'] = hslToHex(h, sat * 0.15, 55);
          scheme['outline-variant'] = hslToHex(h, sat * 0.1, 80);
          scheme['error'] = '#ba1a1a'; scheme['on-error'] = '#ffffff';
          scheme['error-container'] = '#ffdad6'; scheme['on-error-container'] = '#410002';
        }
        return scheme;
      }

      // ── Apply changes to the live page ──
      function applyTheme() {
        var scheme = generateScheme(state.darkMode);
        var root = document.documentElement;
        for (var key in scheme) {
          root.style.setProperty('--md-sys-color-' + key, scheme[key]);
        }
        updateTOML();
      }

      function applyFonts() {
        var root = document.documentElement;
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
      }

      function applyShape() {
        var root = document.documentElement;
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
      }

      function generateTOML() {
        return [
          '# MaterialDocs theme configuration',
          '# Generated by MaterialDocs.editor()',
          '',
          '[theme]',
          'seed = "' + state.seed + '"',
          'secondary_seed = "' + state.secondary + '"',
          'tertiary_seed = "' + state.tertiary + '"',
          'display_font = "' + state.displayFont + '"',
          'body_font = "' + state.bodyFont + '"',
          'code_font = "' + state.codeFont + '"',
          'corner_radius = "' + state.cornerRadius + '"',
        ].join('\\n') + '\\n';
      }

      function updateTOML() {
        var pre = document.getElementById('ed-toml-preview');
        if (pre) pre.textContent = generateTOML();
      }

      updateTOML();
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
