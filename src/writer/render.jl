#=
Render — entry point for the MaterialDocs writer pipeline.

Orchestrates the full build: theme resolution → CSS generation →
navigation tree → page rendering → search index.
=#

import Documenter

"""
    render(doc::Documenter.Document, settings::Material3)

Main entry point for the MaterialDocs writer. Called by the FormatSelector
dispatch system when `Material3()` is passed as the format.

Pipeline:
1. Resolve theme → generate color schemes (light + dark)
2. Build CSS (tokens + static stylesheets) → write `materialdocs.css`
3. Build JS bundle → write `materialdocs.js`
4. Copy assets (logo, favicon, custom CSS/JS, images)
5. Build navigation tree from `doc.internal.navtree`
6. Render each page to HTML
7. Build and write search index JSON
"""
function render(doc::Documenter.Document, settings::Material3)
    @info "MaterialDocs: rendering with theme \"$(settings.theme.name)\""

    # Build directory
    build_dir = doc.user.build

    # 1. Generate color schemes from theme seed
    theme = settings.theme
    light_scheme, dark_scheme = color_scheme_pair(
        theme.seed;
        secondary = theme.secondary_seed,
        tertiary = theme.tertiary_seed,
    )

    # 2. Build assets directory
    assets_dir = joinpath(build_dir, "assets")
    isdir(assets_dir) || mkpath(assets_dir)

    # 3. Generate and write CSS
    css_content = build_css(theme, light_scheme, dark_scheme, settings)
    write(joinpath(assets_dir, "materialdocs.css"), css_content)

    # 4. Generate and write JS
    js_content = build_js(settings)
    write(joinpath(assets_dir, "materialdocs.js"), js_content)

    # 5. Copy user assets
    copy_assets(doc, settings, assets_dir)

    # 6. Build navigation context
    nav_ctx = build_nav_context(doc)

    # 7. Render each page
    for (src, page) in doc.blueprint.pages
        render_page(doc, settings, page, nav_ctx, light_scheme, dark_scheme)
    end

    # 8. Build search index
    if settings.search
        search_index = build_search_index(doc)
        write(joinpath(assets_dir, "search-index.json"), search_index)
    end

    @info "MaterialDocs: build complete ($(length(doc.blueprint.pages)) pages)"
end

# ─────────────────────────────────────────────────────────────────────────────
# CSS generation
# ─────────────────────────────────────────────────────────────────────────────

"""Build the complete CSS string: token block + static styles."""
function build_css(theme::ThemeConfig, light::Dict{Symbol,String},
                   dark::Dict{Symbol,String}, settings::Material3)::String
    io = IOBuffer()

    # CSS custom property tokens (light, dark via media query, dark via toggle)
    _write_css_tokens(io, theme, light, dark, settings)

    # Static component styles will be added in Phase 5
    # For now, include a minimal reset
    print(io, """

/* ── Reset & Base ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html { font-size: 16px; -webkit-font-smoothing: antialiased; scroll-behavior: smooth; }
body {
    font-family: var(--md-sys-typescale-body-large-font);
    font-size: var(--md-sys-typescale-body-large-size);
    line-height: var(--md-sys-typescale-body-large-line-height);
    background: var(--md-sys-color-surface);
    color: var(--md-sys-color-on-surface);
}
a { color: var(--md-sys-color-primary); text-decoration: none; }
a:hover { text-decoration: underline; }
code, pre { font-family: var(--md-sys-typescale-body-large-code-font); }
pre {
    padding: 1rem;
    border-radius: var(--md-sys-shape-corner-medium);
    background: var(--md-sys-color-surface-container);
    overflow-x: auto;
}

/* ── Layout ── */
.md-layout {
    display: grid;
    grid-template-columns: 280px 1fr 220px;
    min-height: 100vh;
    max-width: 1440px;
    margin: 0 auto;
}
.md-sidebar { padding: 1.5rem 1rem; border-right: 1px solid var(--md-sys-color-outline-variant); }
.md-content { padding: 2rem 2.5rem; max-width: 52rem; }
.md-toc { padding: 1.5rem 1rem; border-left: 1px solid var(--md-sys-color-outline-variant); }

/* ── Navbar ── */
.md-navbar {
    position: sticky; top: 0; z-index: 100;
    background: var(--md-sys-color-surface);
    border-bottom: 1px solid var(--md-sys-color-outline-variant);
    padding: 0.75rem 1.5rem;
    display: flex; align-items: center; gap: 1rem;
}
.md-navbar-title {
    font-family: var(--md-sys-typescale-title-large-font);
    font-weight: var(--md-sys-typescale-title-large-weight);
    font-size: var(--md-sys-typescale-title-large-size);
    color: var(--md-sys-color-on-surface);
}

@media (max-width: 1024px) {
    .md-layout { grid-template-columns: 1fr; }
    .md-sidebar, .md-toc { display: none; }
    .md-content { padding: 1.5rem 1rem; }
}
""")

    String(take!(io))
end

"""Write MD3 color tokens as CSS custom properties."""
function _write_css_tokens(io::IO, theme::ThemeConfig,
                           light::Dict{Symbol,String}, dark::Dict{Symbol,String},
                           settings::Material3)
    radii = CORNER_RADII[theme.corner_radius]
    font_display = _css_font_stack(theme.display_font, :display)
    font_body = _css_font_stack(theme.body_font, :body)
    font_code = _css_font_stack(theme.code_font, :code)

    # ── Light (default) ──
    println(io, ":root {")
    _write_color_vars(io, light, theme.custom_colors)
    _write_typography_vars(io, font_display, font_body, font_code)
    _write_shape_vars(io, radii)
    _write_elevation_vars(io)
    _write_motion_vars(io)
    println(io, "}")

    # ── System-preference dark ──
    if settings.dark_mode in (:auto, :toggle)
        println(io, "\n@media (prefers-color-scheme: dark) {")
        println(io, "  :root:not([data-theme=\"light\"]) {")
        _write_color_vars(io, dark, theme.custom_colors; indent="    ")
        println(io, "  }")
        println(io, "}")
    end

    # ── Explicit dark toggle ──
    if settings.dark_mode in (:auto, :toggle, :dark)
        println(io, "\n:root[data-theme=\"dark\"] {")
        _write_color_vars(io, dark, theme.custom_colors; indent="  ")
        println(io, "}")
    end
end

"""Write color role CSS custom properties."""
function _write_color_vars(io::IO, scheme::Dict{Symbol,String},
                           overrides::Dict{String,String};
                           indent::String = "  ")
    for (role, hex) in sort(collect(scheme); by=first)
        css_name = replace(string(role), '_' => '-')
        # Apply override if provided
        value = get(overrides, css_name, hex)
        println(io, indent, "--md-sys-color-", css_name, ": ", value, ";")
    end
end

"""Write typography CSS custom properties (MD3 type scale)."""
function _write_typography_vars(io::IO, display_font::String,
                                body_font::String, code_font::String)
    # MD3 type scale: 15 roles organized by category
    #   display (large/medium/small), headline (l/m/s),
    #   title (l/m/s), body (l/m/s), label (l/m/s)
    typescale = [
        # (role, font_ref, size_rem, line_height_rem, weight, tracking_em)
        ("display-large",  :display, "3.5625rem",  "4rem",      700, "-0.015em"),
        ("display-medium", :display, "2.8125rem",  "3.25rem",   700, "-0.01em"),
        ("display-small",  :display, "2.25rem",    "2.75rem",   600, "0em"),
        ("headline-large",  :display, "2rem",      "2.5rem",    700, "0em"),
        ("headline-medium", :display, "1.75rem",   "2.25rem",   600, "0em"),
        ("headline-small",  :display, "1.5rem",    "2rem",      600, "0em"),
        ("title-large",  :body, "1.375rem", "1.75rem",  600, "0em"),
        ("title-medium", :body, "1rem",     "1.5rem",   600, "0.01em"),
        ("title-small",  :body, "0.875rem", "1.25rem",  500, "0.006em"),
        ("body-large",  :body, "1rem",     "1.5rem",   400, "0.009em"),
        ("body-medium", :body, "0.875rem", "1.25rem",  400, "0.016em"),
        ("body-small",  :body, "0.75rem",  "1rem",     400, "0.025em"),
        ("label-large",  :body, "0.875rem", "1.25rem", 500, "0.006em"),
        ("label-medium", :body, "0.75rem",  "1rem",    500, "0.031em"),
        ("label-small",  :body, "0.6875rem","1rem",    500, "0.031em"),
    ]

    fonts = Dict(:display => display_font, :body => body_font)

    println(io, "  /* Typography */")
    for (role, font_ref, size, lh, weight, tracking) in typescale
        font = fonts[font_ref]
        println(io, "  --md-sys-typescale-", role, "-font: ", font, ";")
        println(io, "  --md-sys-typescale-", role, "-size: ", size, ";")
        println(io, "  --md-sys-typescale-", role, "-line-height: ", lh, ";")
        println(io, "  --md-sys-typescale-", role, "-weight: ", weight, ";")
        println(io, "  --md-sys-typescale-", role, "-tracking: ", tracking, ";")
    end
    println(io, "  --md-sys-typescale-body-large-code-font: ", code_font, ";")
end

"""Write shape corner radius CSS custom properties."""
function _write_shape_vars(io::IO, radii::NTuple{6,Int})
    names = ("extra-small", "small", "medium", "large", "extra-large", "full")
    println(io, "  /* Shape */")
    for (name, r) in zip(names, radii)
        println(io, "  --md-sys-shape-corner-", name, ": ", r, "px;")
    end
end

"""Write elevation CSS custom properties (static box-shadow values)."""
function _write_elevation_vars(io::IO)
    println(io, "  /* Elevation */")
    println(io, "  --md-sys-elevation-0: none;")
    println(io, "  --md-sys-elevation-1: 0 1px 2px rgba(0,0,0,0.3), 0 1px 3px 1px rgba(0,0,0,0.15);")
    println(io, "  --md-sys-elevation-2: 0 1px 2px rgba(0,0,0,0.3), 0 2px 6px 2px rgba(0,0,0,0.15);")
    println(io, "  --md-sys-elevation-3: 0 4px 8px 3px rgba(0,0,0,0.15), 0 1px 3px rgba(0,0,0,0.3);")
    println(io, "  --md-sys-elevation-4: 0 6px 10px 4px rgba(0,0,0,0.15), 0 2px 3px rgba(0,0,0,0.3);")
    println(io, "  --md-sys-elevation-5: 0 8px 12px 6px rgba(0,0,0,0.15), 0 4px 4px rgba(0,0,0,0.3);")
end

"""Write motion/easing CSS custom properties."""
function _write_motion_vars(io::IO)
    println(io, "  /* Motion */")
    println(io, "  --md-sys-motion-easing-standard: cubic-bezier(0.2, 0, 0, 1);")
    println(io, "  --md-sys-motion-easing-standard-decelerate: cubic-bezier(0, 0, 0, 1);")
    println(io, "  --md-sys-motion-easing-standard-accelerate: cubic-bezier(0.3, 0, 1, 1);")
    println(io, "  --md-sys-motion-easing-emphasized: cubic-bezier(0.2, 0, 0, 1);")
    println(io, "  --md-sys-motion-easing-emphasized-decelerate: cubic-bezier(0.05, 0.7, 0.1, 1);")
    println(io, "  --md-sys-motion-easing-emphasized-accelerate: cubic-bezier(0.3, 0, 0.8, 0.15);")
    println(io, "  --md-sys-motion-duration-short1: 50ms;")
    println(io, "  --md-sys-motion-duration-short2: 100ms;")
    println(io, "  --md-sys-motion-duration-medium1: 250ms;")
    println(io, "  --md-sys-motion-duration-medium2: 400ms;")
    println(io, "  --md-sys-motion-duration-long1: 450ms;")
    println(io, "  --md-sys-motion-duration-long2: 700ms;")
end

"""Build a CSS font-family stack with appropriate fallbacks."""
function _css_font_stack(font_name::AbstractString, category::Symbol)::String
    # Check if the font name looks like a serif font
    serif_hints = ("Serif", "Literata", "Lora", "Baskerville", "Bitter", "Playfair",
                   "Merriweather", "Crimson", "Garamond", "Fraunces")
    is_serif = any(h -> occursin(h, font_name), serif_hints)

    if category == :code
        "'$font_name', 'Menlo', 'Consolas', monospace"
    elseif is_serif
        "'$font_name', Georgia, 'Times New Roman', serif"
    else
        "'$font_name', system-ui, -apple-system, sans-serif"
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# JS generation
# ─────────────────────────────────────────────────────────────────────────────

"""Build the JS bundle string."""
function build_js(settings::Material3)::String
    # Minimal JS for Phase 2 — theme toggle + basics
    # Full JS (search, sidebar, TOC spy, copy) comes in Phase 6
    js = """
    // MaterialDocs.js — generated by MaterialDocs.jl
    'use strict';
    """

    if settings.dark_mode == :toggle
        js *= """

    // Dark mode toggle
    (function() {
        const toggle = document.getElementById('md-theme-toggle');
        if (!toggle) return;
        const saved = localStorage.getItem('md-theme');
        if (saved) document.documentElement.setAttribute('data-theme', saved);
        toggle.addEventListener('click', function() {
            const current = document.documentElement.getAttribute('data-theme');
            const next = current === 'dark' ? 'light' : 'dark';
            document.documentElement.setAttribute('data-theme', next);
            localStorage.setItem('md-theme', next);
        });
    })();
    """
    end

    js
end

# ─────────────────────────────────────────────────────────────────────────────
# Asset copying
# ─────────────────────────────────────────────────────────────────────────────

"""Copy user-specified assets (logo, favicon, custom CSS/JS) to build dir."""
function copy_assets(doc::Documenter.Document, settings::Material3,
                     assets_dir::String)
    src_dir = joinpath(doc.user.root, doc.user.source)

    # Copy logo
    if settings.logo !== nothing
        logo_src = joinpath(src_dir, settings.logo)
        if isfile(logo_src)
            cp(logo_src, joinpath(assets_dir, basename(settings.logo)); force=true)
        else
            @warn "MaterialDocs: logo file not found: $logo_src"
        end
    end

    # Copy favicon
    if settings.favicon !== nothing
        fav_src = joinpath(src_dir, settings.favicon)
        if isfile(fav_src)
            cp(fav_src, joinpath(assets_dir, basename(settings.favicon)); force=true)
        else
            @warn "MaterialDocs: favicon file not found: $fav_src"
        end
    end

    # Copy custom CSS files
    for css_file in settings.custom_css
        css_src = joinpath(src_dir, css_file)
        if isfile(css_src)
            cp(css_src, joinpath(assets_dir, basename(css_file)); force=true)
        else
            @warn "MaterialDocs: custom CSS file not found: $css_src"
        end
    end

    # Copy custom JS files
    for js_file in settings.custom_js
        js_src = joinpath(src_dir, js_file)
        if isfile(js_src)
            cp(js_src, joinpath(assets_dir, basename(js_file)); force=true)
        else
            @warn "MaterialDocs: custom JS file not found: $js_src"
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Search index (scaffold)
# ─────────────────────────────────────────────────────────────────────────────

"""Build a JSON search index from all pages. Full implementation in Phase 7."""
function build_search_index(doc::Documenter.Document)::String
    # Scaffold — returns empty array for now
    "[]"
end
