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

    # Build directory (absolute path)
    build_dir = joinpath(doc.user.root, doc.user.build)

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

"""Build the complete CSS string: generated token block + static stylesheets."""
function build_css(theme::ThemeConfig, light::Dict{Symbol,String},
                   dark::Dict{Symbol,String}, settings::Material3)::String
    io = IOBuffer()

    # CSS custom property tokens (light, dark via media query, dark via toggle)
    _write_css_tokens(io, theme, light, dark, settings)
    println(io)

    # Static CSS files — read from src/css/ and concatenate
    css_dir = joinpath(@__DIR__, "..", "css")
    for file in ("base.css", "components.css", "nav.css", "highlight.css", "print.css")
        path = joinpath(css_dir, file)
        if isfile(path)
            println(io, "\n/* ── ", file, " ── */")
            print(io, read(path, String))
            println(io)
        end
    end

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
    _write_highlight_vars(io, :light)
    println(io, "}")

    # ── System-preference dark ──
    if settings.dark_mode in (:auto, :toggle)
        println(io, "\n@media (prefers-color-scheme: dark) {")
        println(io, "  :root:not([data-theme=\"light\"]) {")
        _write_color_vars(io, dark, theme.custom_colors; indent="    ")
        _write_highlight_vars(io, :dark; indent="    ")
        println(io, "  }")
        println(io, "}")
    end

    # ── Explicit dark toggle ──
    if settings.dark_mode in (:auto, :toggle, :dark)
        println(io, "\n:root[data-theme=\"dark\"] {")
        _write_color_vars(io, dark, theme.custom_colors; indent="  ")
        _write_highlight_vars(io, :dark; indent="  ")
        println(io, "}")
    end

    # ── Theme-toggle icon swap ──
    # The button shows the mode you'd switch TO: a moon in light themes, a sun
    # in dark ones. Driven by CSS so it stays correct before JS runs. Emitted
    # only for :toggle — the other modes have no button, and :light must stay
    # free of any dark-mode selectors.
    if settings.dark_mode == :toggle
        println(io, "\n@media (prefers-color-scheme: dark) {")
        println(io, "  :root:not([data-theme=\"light\"]) .md-icon-light { display: block; }")
        println(io, "  :root:not([data-theme=\"light\"]) .md-icon-dark { display: none; }")
        println(io, "}")
        println(io, ":root[data-theme=\"dark\"] .md-icon-light { display: block; }")
        println(io, ":root[data-theme=\"dark\"] .md-icon-dark { display: none; }")
        println(io, ":root[data-theme=\"light\"] .md-icon-light { display: none; }")
        println(io, ":root[data-theme=\"light\"] .md-icon-dark { display: block; }")
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

"""Write syntax highlighting color tokens (GitHub-inspired light/dark palettes)."""
function _write_highlight_vars(io::IO, mode::Symbol; indent::String = "  ")
    # GitHub-inspired palettes that work well on both light and dark backgrounds
    palette = if mode == :light
        Dict(
            "keyword"      => "#cf222e",   # red — control flow, keywords
            "string"       => "#0a3069",   # dark blue — string literals
            "number"       => "#0550ae",   # blue — numeric constants
            "comment"      => "#6e7781",   # grey — comments
            "function"     => "#8250df",   # purple — function names
            "type"         => "#953800",   # orange — type names
            "builtin"      => "#0550ae",   # blue — built-in functions
            "literal"      => "#0550ae",   # blue — true/false/nothing
            "variable"     => "#24292f",   # near-black — variables
            "operator"     => "#cf222e",   # red — operators
            "punctuation"  => "#24292f",   # near-black — punctuation
            "attr"         => "#116329",   # green — attributes
            "meta"         => "#8250df",   # purple — macros/directives
            "deletion"     => "#82071e",   # dark red — diff deletions
            "deletion-bg"  => "#ffebe9",   # light red bg
            "addition"     => "#116329",   # green — diff additions
            "addition-bg"  => "#dafbe1",   # light green bg
        )
    else
        Dict(
            "keyword"      => "#ff7b72",   # salmon — control flow, keywords
            "string"       => "#a5d6ff",   # light blue — string literals
            "number"       => "#79c0ff",   # blue — numeric constants
            "comment"      => "#8b949e",   # grey — comments
            "function"     => "#d2a8ff",   # lavender — function names
            "type"         => "#ffa657",   # orange — type names
            "builtin"      => "#79c0ff",   # blue — built-in functions
            "literal"      => "#79c0ff",   # blue — true/false/nothing
            "variable"     => "#c9d1d9",   # light grey — variables
            "operator"     => "#ff7b72",   # salmon — operators
            "punctuation"  => "#c9d1d9",   # light grey — punctuation
            "attr"         => "#7ee787",   # green — attributes
            "meta"         => "#d2a8ff",   # lavender — macros/directives
            "deletion"     => "#ffa198",   # light red — diff deletions
            "deletion-bg"  => "#490202",   # dark red bg
            "addition"     => "#7ee787",   # green — diff additions
            "addition-bg"  => "#04260f",   # dark green bg
        )
    end

    println(io, indent, "/* Syntax highlighting */")
    for key in sort(collect(keys(palette)))
        println(io, indent, "--md-code-", key, ": ", palette[key], ";")
    end
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

"""Build the JS bundle string: static modules concatenated."""
function build_js(settings::Material3)::String
    io = IOBuffer()
    println(io, "// MaterialDocs.js — generated by MaterialDocs.jl")
    println(io, "'use strict';")

    js_dir = joinpath(@__DIR__, "..", "js")

    # Theme toggle — only when dark_mode is :toggle
    if settings.dark_mode == :toggle
        _append_js_file(io, js_dir, "theme-toggle.js")
    end

    # Always include these modules
    for file in ("sidebar.js", "copy.js", "toc.js")
        _append_js_file(io, js_dir, file)
    end

    # Search — only when search is enabled
    if settings.search
        _append_js_file(io, js_dir, "search.js")
    end

    # Version selector — only when versions are enabled
    if settings.versions
        _append_js_file(io, js_dir, "versions.js")
    end

    String(take!(io))
end

"""Append a JS file to the bundle if it exists."""
function _append_js_file(io::IO, js_dir::String, file::String)
    path = joinpath(js_dir, file)
    if isfile(path)
        println(io, "\n/* ── ", file, " ── */")
        print(io, read(path, String))
        println(io)
    end
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
# Search index
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_search_index(doc::Documenter.Document) → String

Build a JSON search index from all pages for client-side search.

Each entry has:
- `title`: heading text (or page title for the page-level entry)
- `text`: plain text under that heading (truncated to ~300 chars)
- `href`: relative URL to the page + anchor (prettyurl-aware)
- `section`: parent page title (for sub-headings)
"""
function build_search_index(doc::Documenter.Document)::String
    entries = Dict{String,Any}[]

    for (src, page) in doc.blueprint.pages
        page_title = _page_title_from_page(page)

        # Compute page URL (relative to build root)
        # Normalize separators to "/" for consistent matching across platforms
        _norm(p) = replace(p, '\\' => '/')
        page_build_html = replace(page.build, r"\.md$" => ".html")
        build_prefix = _norm(doc.user.build) * "/"
        page_build_norm = _norm(page_build_html)
        page_rel = startswith(page_build_norm, build_prefix) ?
            page_build_norm[length(build_prefix)+1:end] : page_build_norm
        page_href = _nav_href(page_rel, true)  # always prettyurl for search

        # Walk AST, splitting into sections by heading
        sections = _split_page_sections(page)

        for (i, sec) in enumerate(sections)
            anchor = sec.slug
            href = isempty(anchor) ? page_href : page_href * "#" * anchor
            title = isempty(sec.title) ? page_title : sec.title
            section_label = (i == 1 || isempty(sec.title)) ? "" : page_title

            text = _truncate_text(sec.text, 300)
            push!(entries, Dict{String,Any}(
                "title" => title,
                "text" => text,
                "href" => href,
                "section" => section_label,
            ))
        end
    end

    _entries_to_json(entries)
end

"""A section of a page: heading + body text."""
struct SearchSection
    title::String
    slug::String
    text::String
end

"""Split a page's AST into sections delimited by headings.
Each docstring also becomes its own entry (binding name as title)."""
function _split_page_sections(page::Documenter.Page)::Vector{SearchSection}
    sections = SearchSection[]
    current_title = ""
    current_slug = ""
    buf = IOBuffer()

    mdast = page.mdast
    for child in mdast.children
        heading_node, slug = _extract_heading(child)
        if heading_node !== nothing
            # Flush previous section
            text = strip(String(take!(buf)))
            if !isempty(current_title) || !isempty(text)
                push!(sections, SearchSection(current_title, current_slug, text))
            end
            current_title = _collect_text(heading_node)
            current_slug = slug
            buf = IOBuffer()
        else
            # Check for DocsNode or DocsNodesBlock — emit each docstring
            # as its own search entry for precise matching
            docsnodes = _collect_docsnodes(child)
            if !isempty(docsnodes)
                # Flush any accumulated text before docstrings
                text = strip(String(take!(buf)))
                if !isempty(text)
                    push!(sections, SearchSection(current_title, current_slug, text))
                    buf = IOBuffer()
                end
                for dn in docsnodes
                    _emit_docsnode_section!(sections, dn)
                end
            else
                # Accumulate plain text
                _collect_plain_text(buf, child)
                print(buf, ' ')
            end
        end
    end

    # Flush final section
    text = strip(String(take!(buf)))
    if !isempty(current_title) || !isempty(text)
        push!(sections, SearchSection(current_title, current_slug, text))
    end

    # If no sections at all, create one from the page
    if isempty(sections)
        push!(sections, SearchSection("", "", ""))
    end

    sections
end

"""Collect DocsNode elements from a node (handles DocsNodesBlock containers)."""
function _collect_docsnodes(node)::Vector{Any}
    elem = node.element
    if elem isa Documenter.DocsNode
        return [elem]
    elseif elem isa Documenter.DocsNodesBlock
        result = []
        for child in node.children
            if child.element isa Documenter.DocsNode
                push!(result, child.element)
            end
        end
        return result
    end
    return []
end

"""Emit a DocsNode as its own SearchSection entry."""
function _emit_docsnode_section!(sections::Vector{SearchSection}, dn::Documenter.DocsNode)
    binding = string(dn.object.binding)
    slug = Documenter.anchor_label(dn.anchor)

    buf = IOBuffer()
    # Add signature
    if dn.object.signature !== Union{}
        print(buf, string(dn.object.signature), ' ')
    end
    # Extract docstring text
    for mdast in dn.mdasts
        for child in mdast.children
            _collect_plain_text(buf, child)
            print(buf, ' ')
        end
    end
    text = strip(String(take!(buf)))
    push!(sections, SearchSection(binding, slug, text))
end

"""Recursively extract plain text from an AST node (no HTML)."""
function _collect_plain_text(io::IO, node)
    elem = node.element
    if elem isa MarkdownAST.Text
        print(io, elem.text)
    elseif elem isa MarkdownAST.Code
        print(io, elem.code)
    elseif elem isa MarkdownAST.CodeBlock
        print(io, elem.code)
    elseif elem isa MarkdownAST.SoftBreak || elem isa MarkdownAST.LineBreak
        print(io, ' ')
    elseif elem isa MarkdownAST.ThematicBreak
        # skip
    elseif elem isa Documenter.DocsNode
        # Index the binding name and signature
        print(io, string(elem.object.binding), ' ')
        if elem.object.signature !== Union{}
            print(io, string(elem.object.signature), ' ')
        end
        # Extract text from each docstring's markdown AST
        for mdast in elem.mdasts
            for child in mdast.children
                _collect_plain_text(io, child)
                print(io, ' ')
            end
        end
    elseif elem isa Documenter.DocsNodesBlock
        # Container for DocsNode nodes — recurse into children
        for child in node.children
            _collect_plain_text(io, child)
        end
    elseif elem isa Documenter.MultiOutput
        # Multi-output blocks — extract code from children
        for child in node.children
            _collect_plain_text(io, child)
        end
    elseif elem isa Documenter.MultiOutputElement
        result = elem.element
        if result isa Dict && haskey(result, MIME"text/plain"())
            print(io, result[MIME"text/plain"()], ' ')
        else
            for child in node.children
                _collect_plain_text(io, child)
            end
        end
    else
        # Recurse into children (paragraphs, emphasis, strong, lists, etc.)
        for child in node.children
            _collect_plain_text(io, child)
        end
    end
end

"""Truncate text to approximately n characters at a word boundary."""
function _truncate_text(text::String, n::Int)::String
    length(text) <= n && return text
    # Find last space before the limit
    idx = findprev(' ', text, n)
    idx === nothing && (idx = n)
    text[1:idx] * "…"
end

"""Serialize search entries to JSON (no external dependency)."""
function _entries_to_json(entries::Vector{Dict{String,Any}})::String
    io = IOBuffer()
    print(io, '[')
    for (i, entry) in enumerate(entries)
        i > 1 && print(io, ',')
        print(io, '{')
        first_field = true
        for key in ("title", "text", "href", "section")
            val = get(entry, key, "")
            !first_field && print(io, ',')
            first_field = false
            print(io, '"', key, '"', ':', '"', _json_escape(val), '"')
        end
        print(io, '}')
    end
    print(io, ']')
    String(take!(io))
end

"""Escape a string for JSON output."""
function _json_escape(s::AbstractString)::String
    replace(s,
        '\\' => "\\\\",
        '"' => "\\\"",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
    )
end
