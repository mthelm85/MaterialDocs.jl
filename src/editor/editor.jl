#=
Theme Editor — interactive browser-based theme configurator.

`MaterialDocs.editor()` opens a standalone HTML page in the default browser
with live preview of MD3 components. The editor uses a simplified HSL-based
color approximation for instant preview; the actual build uses the full HCT
engine for accurate Material Design 3 colors.
=#

"""
    editor(; theme::ThemeConfig = resolve_theme(:default), port::Nothing = nothing)

Launch the MaterialDocs theme editor in your default browser.

Opens a self-contained HTML page with:
- **Color pickers** for seed, secondary, and tertiary colors
- **Font selectors** for display, body, and code fonts
- **Shape controls** for corner radius
- **Live preview** of MD3 components (headings, code blocks, admonitions, etc.)
- **TOML export** — copy or download `.materialdocs.toml` configuration

The preview uses approximate colors; the actual `makedocs` build computes
precise Material Design 3 color schemes via the HCT engine.

# Example
```julia
using MaterialDocs
MaterialDocs.editor()

# Start with a specific theme
MaterialDocs.editor(theme = resolve_theme(:ocean_depth))
```
"""
function editor(; theme::ThemeConfig = resolve_theme(:default))
    html = _generate_editor_html(theme)
    path = joinpath(tempdir(), "materialdocs-editor.html")
    write(path, html)
    _open_in_browser(path)
    @info "MaterialDocs theme editor opened in your browser" path
    path
end

"""Open a file in the default browser (cross-platform)."""
function _open_in_browser(path::String)
    if Sys.iswindows()
        run(`cmd /c start "" "$path"`)
    elseif Sys.isapple()
        run(`open "$path"`)
    else
        run(`xdg-open "$path"`)
    end
end

"""Generate the self-contained editor HTML page."""
function _generate_editor_html(theme::ThemeConfig)::String
    # Pre-compute initial color scheme for defaults
    light, dark = color_scheme_pair(theme.seed;
        secondary = theme.secondary_seed,
        tertiary = theme.tertiary_seed)

    # Build initial CSS tokens
    initial_tokens = _editor_initial_tokens(light, theme)

    # Resolve nothing seeds to the primary seed for display
    sec_seed = something(theme.secondary_seed, theme.seed)
    ter_seed = something(theme.tertiary_seed, theme.seed)

    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>MaterialDocs Theme Editor</title>
    <style>
    $(_editor_css())
    </style>
    </head>
    <body>
    <div class="ed-layout">
      <div class="ed-panel">
        <h1 class="ed-title">🎨 MaterialDocs Theme Editor</h1>

        <section class="ed-section">
          <h2 class="ed-section-title">Colors</h2>
          <div class="ed-field">
            <label for="seed">Seed Color</label>
            <div class="ed-color-row">
              <input type="color" id="seed" value="$(theme.seed)">
              <input type="text" id="seed-hex" value="$(theme.seed)" class="ed-hex">
            </div>
          </div>
          <div class="ed-field">
            <label for="secondary">Secondary Seed</label>
            <div class="ed-color-row">
              <input type="color" id="secondary" value="$(sec_seed)">
              <input type="text" id="secondary-hex" value="$(sec_seed)" class="ed-hex">
            </div>
          </div>
          <div class="ed-field">
            <label for="tertiary">Tertiary Seed</label>
            <div class="ed-color-row">
              <input type="color" id="tertiary" value="$(ter_seed)">
              <input type="text" id="tertiary-hex" value="$(ter_seed)" class="ed-hex">
            </div>
          </div>
        </section>

        <section class="ed-section">
          <h2 class="ed-section-title">Typography</h2>
          <div class="ed-field">
            <label for="display-font">Display Font</label>
            <select id="display-font">
              $(_font_options(theme.display_font, :display))
            </select>
          </div>
          <div class="ed-field">
            <label for="body-font">Body Font</label>
            <select id="body-font">
              $(_font_options(theme.body_font, :body))
            </select>
          </div>
          <div class="ed-field">
            <label for="code-font">Code Font</label>
            <select id="code-font">
              $(_font_options(theme.code_font, :code))
            </select>
          </div>
        </section>

        <section class="ed-section">
          <h2 class="ed-section-title">Shape</h2>
          <div class="ed-field">
            <label for="corner-radius">Corner Radius</label>
            <select id="corner-radius">
              <option value="sharp"$(_sel(theme.corner_radius, :sharp))>Sharp</option>
              <option value="default"$(_sel(theme.corner_radius, :default))>Default</option>
              <option value="rounded"$(_sel(theme.corner_radius, :rounded))>Rounded</option>
              <option value="pill"$(_sel(theme.corner_radius, :pill))>Pill</option>
            </select>
          </div>
        </section>

        <section class="ed-section">
          <h2 class="ed-section-title">Export</h2>
          <button id="copy-toml" class="ed-btn ed-btn-primary">📋 Copy TOML</button>
          <button id="download-toml" class="ed-btn">💾 Download .materialdocs.toml</button>
          <pre id="toml-preview" class="ed-toml-preview"></pre>
        </section>
      </div>

      <div class="ed-preview" id="preview">
        <div class="ed-preview-toolbar">
          <span class="ed-preview-label">Live Preview</span>
          <button id="toggle-dark" class="ed-btn-small">🌙 Dark</button>
        </div>
        <div class="ed-preview-frame" id="preview-frame">
          $(_preview_html())
        </div>
      </div>
    </div>

    <script>
    $(_editor_js(theme))
    </script>
    </body>
    </html>
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
    # Ensure current is in the list
    current in fonts || pushfirst!(fonts, current)
    io = IOBuffer()
    for f in fonts
        sel = f == current ? " selected" : ""
        println(io, "<option value=\"$f\"$sel>$f</option>")
    end
    String(take!(io))
end

"""Build initial CSS tokens from the Julia-computed color scheme."""
function _editor_initial_tokens(scheme::Dict{Symbol,String}, theme::ThemeConfig)::String
    io = IOBuffer()
    for (role, hex) in sort(collect(scheme); by=Base.first)
        css_name = replace(string(role), '_' => '-')
        println(io, "--md-sys-color-$css_name: $hex;")
    end
    String(take!(io))
end

"""Generate the editor panel CSS."""
function _editor_css()::String
    """
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      background: #f5f5f5;
      color: #1a1a1a;
    }
    .ed-layout {
      display: grid;
      grid-template-columns: 340px 1fr;
      height: 100vh;
    }
    .ed-panel {
      padding: 1.25rem;
      overflow-y: auto;
      background: #fff;
      border-right: 1px solid #e0e0e0;
    }
    .ed-title {
      font-size: 1.25rem;
      margin-bottom: 1.25rem;
      padding-bottom: 0.75rem;
      border-bottom: 1px solid #e0e0e0;
    }
    .ed-section {
      margin-bottom: 1.25rem;
    }
    .ed-section-title {
      font-size: 0.8125rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #666;
      margin-bottom: 0.75rem;
    }
    .ed-field {
      margin-bottom: 0.75rem;
    }
    .ed-field label {
      display: block;
      font-size: 0.8125rem;
      font-weight: 500;
      margin-bottom: 0.25rem;
    }
    .ed-field select, .ed-field input[type="text"] {
      width: 100%;
      padding: 0.375rem 0.5rem;
      border: 1px solid #ccc;
      border-radius: 6px;
      font-size: 0.875rem;
      background: #fff;
    }
    .ed-color-row {
      display: flex;
      gap: 0.5rem;
      align-items: center;
    }
    .ed-color-row input[type="color"] {
      width: 40px;
      height: 32px;
      border: 1px solid #ccc;
      border-radius: 6px;
      padding: 2px;
      cursor: pointer;
    }
    .ed-hex {
      flex: 1;
      font-family: monospace;
    }
    .ed-btn {
      display: block;
      width: 100%;
      padding: 0.5rem;
      border: 1px solid #ccc;
      border-radius: 8px;
      background: #fff;
      cursor: pointer;
      font-size: 0.875rem;
      margin-bottom: 0.5rem;
      transition: background 0.15s;
    }
    .ed-btn:hover { background: #f0f0f0; }
    .ed-btn-primary {
      background: #1a73e8;
      color: #fff;
      border-color: #1a73e8;
    }
    .ed-btn-primary:hover { background: #1557b0; }
    .ed-btn-small {
      padding: 0.25rem 0.75rem;
      border: 1px solid #ccc;
      border-radius: 6px;
      background: #fff;
      cursor: pointer;
      font-size: 0.8125rem;
    }
    .ed-toml-preview {
      margin-top: 0.5rem;
      padding: 0.75rem;
      background: #f5f5f5;
      border-radius: 8px;
      font-family: monospace;
      font-size: 0.75rem;
      line-height: 1.5;
      white-space: pre-wrap;
      max-height: 200px;
      overflow-y: auto;
    }
    .ed-preview {
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    .ed-preview-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0.5rem 1rem;
      background: #e8e8e8;
      border-bottom: 1px solid #d0d0d0;
    }
    .ed-preview-label {
      font-size: 0.8125rem;
      font-weight: 600;
      color: #666;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .ed-preview-frame {
      flex: 1;
      overflow-y: auto;
      padding: 2rem;
      transition: background 0.3s, color 0.3s;
    }

    /* Preview component styles — use CSS variables */
    .pv { --radius: 12px; }
    .pv-surface { background: var(--md-sys-color-surface); color: var(--md-sys-color-on-surface); padding: 1.5rem; border-radius: var(--radius); min-height: 100%; }
    .pv h1 { font-size: 2rem; font-weight: 700; margin-bottom: 0.5rem; }
    .pv h2 { font-size: 1.5rem; font-weight: 600; margin: 1.25rem 0 0.5rem; color: var(--md-sys-color-on-surface); }
    .pv h3 { font-size: 1.125rem; font-weight: 600; margin: 1rem 0 0.375rem; }
    .pv p { line-height: 1.6; margin-bottom: 0.75rem; color: var(--md-sys-color-on-surface); }
    .pv a { color: var(--md-sys-color-primary); }
    .pv-code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.8125rem;
      background: var(--md-sys-color-surface-container);
      border: 1px solid var(--md-sys-color-outline-variant);
      border-radius: 8px;
      padding: 1rem;
      margin: 0.75rem 0;
      overflow-x: auto;
      color: var(--md-sys-color-on-surface);
    }
    .pv-inline-code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.875em;
      background: var(--md-sys-color-surface-container-high);
      padding: 0.125em 0.35em;
      border-radius: 4px;
    }
    .pv-admonition {
      border-radius: var(--radius);
      border: 1px solid;
      overflow: hidden;
      margin: 0.75rem 0;
    }
    .pv-admonition-title { padding: 0.5rem 1rem; font-weight: 600; font-size: 0.875rem; }
    .pv-admonition-body { padding: 0.75rem 1rem; font-size: 0.875rem; }
    .pv-note { border-color: var(--md-sys-color-primary); }
    .pv-note .pv-admonition-title { background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); }
    .pv-warning { border-color: var(--md-sys-color-secondary); }
    .pv-warning .pv-admonition-title { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); }
    .pv-tip { border-color: var(--md-sys-color-tertiary); }
    .pv-tip .pv-admonition-title { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); }
    .pv-danger { border-color: var(--md-sys-color-error); }
    .pv-danger .pv-admonition-title { background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); }
    .pv-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
      border: 1px solid var(--md-sys-color-outline-variant);
      border-radius: var(--radius);
      overflow: hidden;
      margin: 0.75rem 0;
    }
    .pv-table th {
      text-align: left;
      padding: 0.5rem 1rem;
      background: var(--md-sys-color-surface-container);
      font-weight: 600;
      color: var(--md-sys-color-on-surface);
      border-bottom: 2px solid var(--md-sys-color-outline-variant);
    }
    .pv-table td {
      padding: 0.5rem 1rem;
      border-bottom: 1px solid var(--md-sys-color-outline-variant);
      color: var(--md-sys-color-on-surface);
    }
    .pv-blockquote {
      border-left: 3px solid var(--md-sys-color-outline);
      background: var(--md-sys-color-surface-container-lowest);
      padding: 0.75rem 1.25rem;
      border-radius: 0 8px 8px 0;
      margin: 0.75rem 0;
      color: var(--md-sys-color-on-surface-variant);
    }
    .pv-navbar {
      background: var(--md-sys-color-surface);
      border-bottom: 1px solid var(--md-sys-color-outline-variant);
      padding: 0.625rem 1.25rem;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      border-radius: var(--radius) var(--radius) 0 0;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
    }
    .pv-navbar-title { font-weight: 600; font-size: 1.125rem; color: var(--md-sys-color-on-surface); }
    .pv-chip {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      border-radius: 16px;
      font-size: 0.75rem;
      font-weight: 500;
    }
    .pv-chip-primary { background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); }
    .pv-chip-secondary { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); }
    .pv-chip-tertiary { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); }
    .pv-swatch-row { display: flex; gap: 0.5rem; flex-wrap: wrap; margin: 0.75rem 0; }
    .pv-swatch {
      width: 3rem; height: 3rem;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.6rem;
      font-weight: 600;
    }
    .pv-docstring {
      background: var(--md-sys-color-surface-container-lowest);
      border: 1px solid var(--md-sys-color-outline-variant);
      border-radius: var(--radius);
      padding: 1rem;
      margin: 0.75rem 0;
    }
    .pv-docstring-binding {
      font-family: 'JetBrains Mono', monospace;
      font-weight: 600;
      padding-bottom: 0.5rem;
      border-bottom: 1px solid var(--md-sys-color-outline-variant);
      margin-bottom: 0.5rem;
    }
    .pv-docstring-binding code {
      background: var(--md-sys-color-primary-container);
      color: var(--md-sys-color-on-primary-container);
      padding: 0.125em 0.4em;
      border-radius: 4px;
    }
    """
end

"""Generate preview HTML showing sample components."""
function _preview_html()::String
    """
    <div class="pv">
      <div class="pv-surface">
        <div class="pv-navbar">
          <span class="pv-navbar-title">📦 MyPackage.jl</span>
          <span style="flex:1"></span>
          <span style="color:var(--md-sys-color-on-surface-variant);font-size:0.875rem">🔍</span>
          <span style="color:var(--md-sys-color-on-surface-variant);font-size:0.875rem">🌙</span>
        </div>

        <div style="padding:1.25rem">
          <h1>Welcome to MyPackage.jl</h1>
          <p>A powerful Julia package for <span class="pv-inline-code">doing things</span> efficiently.
          Check out the <a href="#">API Reference</a> for details.</p>

          <div class="pv-swatch-row">
            <div class="pv-swatch" style="background:var(--md-sys-color-primary);color:var(--md-sys-color-on-primary)">P</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-secondary);color:var(--md-sys-color-on-secondary)">S</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-tertiary);color:var(--md-sys-color-on-tertiary)">T</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-error);color:var(--md-sys-color-on-error)">E</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-primary-container);color:var(--md-sys-color-on-primary-container)">PC</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-secondary-container);color:var(--md-sys-color-on-secondary-container)">SC</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-tertiary-container);color:var(--md-sys-color-on-tertiary-container)">TC</div>
            <div class="pv-swatch" style="background:var(--md-sys-color-error-container);color:var(--md-sys-color-on-error-container)">EC</div>
          </div>

          <div style="display:flex;gap:0.5rem;margin:0.75rem 0">
            <span class="pv-chip pv-chip-primary">Primary</span>
            <span class="pv-chip pv-chip-secondary">Secondary</span>
            <span class="pv-chip pv-chip-tertiary">Tertiary</span>
          </div>

          <h2>Getting Started</h2>
          <p>Install the package and start using it right away:</p>

          <div class="pv-code"><span style="color:var(--md-sys-color-primary)">using</span> MyPackage

result = compute(data;
    method = <span style="color:var(--md-sys-color-tertiary)">:fast</span>,
    verbose = <span style="color:var(--md-sys-color-secondary)">true</span>
)</div>

          <div class="pv-admonition pv-note">
            <div class="pv-admonition-title">📘 Note</div>
            <div class="pv-admonition-body">This function requires Julia 1.10 or later. See compatibility notes below.</div>
          </div>

          <div class="pv-admonition pv-warning">
            <div class="pv-admonition-title">⚠️ Warning</div>
            <div class="pv-admonition-body">Large datasets may require significant memory. Consider using the streaming API for files over 1GB.</div>
          </div>

          <div class="pv-admonition pv-tip">
            <div class="pv-admonition-title">💡 Tip</div>
            <div class="pv-admonition-body">For best performance, pre-allocate output arrays with <span class="pv-inline-code">similar(data)</span>.</div>
          </div>

          <div class="pv-admonition pv-danger">
            <div class="pv-admonition-title">🔴 Danger</div>
            <div class="pv-admonition-body">This operation modifies data in-place. Make a copy first if you need the original.</div>
          </div>

          <h2>API Reference</h2>

          <div class="pv-docstring">
            <div class="pv-docstring-binding"><code>compute(data; method, verbose)</code></div>
            <p>Compute the result from <span class="pv-inline-code">data</span> using the specified method.</p>
            <p><strong>Arguments</strong></p>
            <ul style="margin:0.5rem 0;padding-left:1.5rem">
              <li><span class="pv-inline-code">data</span> — input data array</li>
              <li><span class="pv-inline-code">method</span> — algorithm to use (<span class="pv-inline-code">:fast</span> or <span class="pv-inline-code">:accurate</span>)</li>
            </ul>
          </div>

          <h3>Data Table</h3>
          <table class="pv-table">
            <thead><tr><th>Method</th><th>Speed</th><th>Accuracy</th></tr></thead>
            <tbody>
              <tr><td><span class="pv-inline-code">:fast</span></td><td>~2ms</td><td>99.1%</td></tr>
              <tr><td><span class="pv-inline-code">:accurate</span></td><td>~15ms</td><td>99.97%</td></tr>
            </tbody>
          </table>

          <div class="pv-blockquote">
            <p>"Simplicity is the ultimate sophistication." — Leonardo da Vinci</p>
          </div>
        </div>
      </div>
    </div>
    """
end

"""Generate the editor JavaScript."""
function _editor_js(theme::ThemeConfig)::String
    # Pre-compute initial colors
    light, _ = color_scheme_pair(theme.seed;
        secondary = theme.secondary_seed,
        tertiary = theme.tertiary_seed)

    # Build initial token JS object
    initial_tokens_js = _scheme_to_js_object(light)

    sec_seed = something(theme.secondary_seed, theme.seed)
    ter_seed = something(theme.tertiary_seed, theme.seed)

    """
    (function() {
      // ── State ──
      var state = {
        seed: '$(theme.seed)',
        secondary: '$(sec_seed)',
        tertiary: '$(ter_seed)',
        displayFont: '$(theme.display_font)',
        bodyFont: '$(theme.body_font)',
        codeFont: '$(theme.code_font)',
        cornerRadius: '$(theme.corner_radius)',
        darkMode: false
      };

      // Initial tokens from Julia's HCT engine
      var currentTokens = $initial_tokens_js;

      // ── DOM refs ──
      var frame = document.getElementById('preview-frame');
      var tomlPreview = document.getElementById('toml-preview');

      // ── Color sync ──
      ['seed', 'secondary', 'tertiary'].forEach(function(name) {
        var picker = document.getElementById(name);
        var hex = document.getElementById(name + '-hex');
        picker.addEventListener('input', function() {
          hex.value = picker.value;
          state[name] = picker.value;
          updatePreview();
        });
        hex.addEventListener('change', function() {
          if (/^#[0-9a-fA-F]{6}\$/.test(hex.value)) {
            picker.value = hex.value;
            state[name] = hex.value;
            updatePreview();
          }
        });
      });

      // ── Font sync ──
      document.getElementById('display-font').addEventListener('change', function(e) {
        state.displayFont = e.target.value; updatePreview();
      });
      document.getElementById('body-font').addEventListener('change', function(e) {
        state.bodyFont = e.target.value; updatePreview();
      });
      document.getElementById('code-font').addEventListener('change', function(e) {
        state.codeFont = e.target.value; updatePreview();
      });

      // ── Shape sync ──
      document.getElementById('corner-radius').addEventListener('change', function(e) {
        state.cornerRadius = e.target.value; updatePreview();
      });

      // ── Dark mode toggle ──
      document.getElementById('toggle-dark').addEventListener('click', function() {
        state.darkMode = !state.darkMode;
        this.textContent = state.darkMode ? '☀️ Light' : '🌙 Dark';
        updatePreview();
      });

      // ── Export ──
      document.getElementById('copy-toml').addEventListener('click', function() {
        var toml = generateTOML();
        navigator.clipboard.writeText(toml).then(function() {
          var btn = document.getElementById('copy-toml');
          btn.textContent = '✅ Copied!';
          setTimeout(function() { btn.textContent = '📋 Copy TOML'; }, 1500);
        });
      });

      document.getElementById('download-toml').addEventListener('click', function() {
        var toml = generateTOML();
        var blob = new Blob([toml], { type: 'text/plain' });
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url;
        a.download = '.materialdocs.toml';
        a.click();
        URL.revokeObjectURL(url);
      });

      // ── Simplified HSL color engine for preview ──
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
        var toHex = function(v) { var h = Math.round((v + m) * 255).toString(16); return h.length === 1 ? '0' + h : h; };
        return '#' + toHex(r) + toHex(g) + toHex(b);
      }

      function generateScheme(seedHex, isDark) {
        var hsl = hexToHSL(seedHex);
        var h = hsl[0], s = hsl[1];
        var scheme = {};
        if (isDark) {
          scheme.primary = hslToHex(h, s * 0.8, 70);
          scheme['on-primary'] = hslToHex(h, s * 0.5, 15);
          scheme['primary-container'] = hslToHex(h, s * 0.7, 25);
          scheme['on-primary-container'] = hslToHex(h, s * 0.6, 85);
          scheme.surface = hslToHex(h, s * 0.15, 10);
          scheme['on-surface'] = hslToHex(h, s * 0.08, 90);
          scheme['surface-container'] = hslToHex(h, s * 0.12, 15);
          scheme['surface-container-high'] = hslToHex(h, s * 0.1, 20);
          scheme['surface-container-highest'] = hslToHex(h, s * 0.08, 25);
          scheme['surface-container-low'] = hslToHex(h, s * 0.12, 12);
          scheme['surface-container-lowest'] = hslToHex(h, s * 0.1, 6);
          scheme['on-surface-variant'] = hslToHex(h, s * 0.1, 70);
          scheme.outline = hslToHex(h, s * 0.15, 50);
          scheme['outline-variant'] = hslToHex(h, s * 0.1, 30);
        } else {
          scheme.primary = hslToHex(h, s * 0.8, 40);
          scheme['on-primary'] = '#ffffff';
          scheme['primary-container'] = hslToHex(h, s * 0.6, 90);
          scheme['on-primary-container'] = hslToHex(h, s * 0.7, 15);
          scheme.surface = hslToHex(h, s * 0.05, 98);
          scheme['on-surface'] = hslToHex(h, s * 0.08, 12);
          scheme['surface-container'] = hslToHex(h, s * 0.08, 94);
          scheme['surface-container-high'] = hslToHex(h, s * 0.06, 91);
          scheme['surface-container-highest'] = hslToHex(h, s * 0.05, 88);
          scheme['surface-container-low'] = hslToHex(h, s * 0.06, 96);
          scheme['surface-container-lowest'] = '#ffffff';
          scheme['on-surface-variant'] = hslToHex(h, s * 0.1, 35);
          scheme.outline = hslToHex(h, s * 0.15, 55);
          scheme['outline-variant'] = hslToHex(h, s * 0.1, 80);
        }
        return scheme;
      }

      function generateFullScheme(isDark) {
        var primary = generateScheme(state.seed, isDark);
        var sec = hexToHSL(state.secondary);
        var ter = hexToHSL(state.tertiary);
        var sH = sec[0], sS = sec[1];
        var tH = ter[0], tS = ter[1];

        if (isDark) {
          primary.secondary = hslToHex(sH, sS * 0.7, 70);
          primary['on-secondary'] = hslToHex(sH, sS * 0.5, 15);
          primary['secondary-container'] = hslToHex(sH, sS * 0.6, 25);
          primary['on-secondary-container'] = hslToHex(sH, sS * 0.5, 85);
          primary.tertiary = hslToHex(tH, tS * 0.7, 70);
          primary['on-tertiary'] = hslToHex(tH, tS * 0.5, 15);
          primary['tertiary-container'] = hslToHex(tH, tS * 0.6, 25);
          primary['on-tertiary-container'] = hslToHex(tH, tS * 0.5, 85);
          primary.error = '#ffb4ab';
          primary['on-error'] = '#690005';
          primary['error-container'] = '#93000a';
          primary['on-error-container'] = '#ffdad6';
        } else {
          primary.secondary = hslToHex(sH, sS * 0.7, 40);
          primary['on-secondary'] = '#ffffff';
          primary['secondary-container'] = hslToHex(sH, sS * 0.5, 90);
          primary['on-secondary-container'] = hslToHex(sH, sS * 0.6, 15);
          primary.tertiary = hslToHex(tH, tS * 0.7, 40);
          primary['on-tertiary'] = '#ffffff';
          primary['tertiary-container'] = hslToHex(tH, tS * 0.5, 90);
          primary['on-tertiary-container'] = hslToHex(tH, tS * 0.6, 15);
          primary.error = '#ba1a1a';
          primary['on-error'] = '#ffffff';
          primary['error-container'] = '#ffdad6';
          primary['on-error-container'] = '#410002';
        }
        return primary;
      }

      function updatePreview() {
        var scheme = generateFullScheme(state.darkMode);
        var style = frame.style;
        for (var key in scheme) {
          frame.style.setProperty('--md-sys-color-' + key, scheme[key]);
        }

        // Corner radius
        var radii = { sharp: '4px', 'default': '12px', rounded: '20px', pill: '28px' };
        frame.querySelector('.pv').style.setProperty('--radius', radii[state.cornerRadius] || '12px');

        updateTOML();
      }

      function generateTOML() {
        var lines = [
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
        ];
        return lines.join('\\n') + '\\n';
      }

      function updateTOML() {
        tomlPreview.textContent = generateTOML();
      }

      // ── Initial render ──
      // Apply Julia-computed tokens for accurate initial preview
      for (var key in currentTokens) {
        frame.style.setProperty('--md-sys-color-' + key, currentTokens[key]);
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
