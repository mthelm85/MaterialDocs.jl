#=
Page — renders individual documentation pages to HTML files.

Generates the full HTML document: head, navbar, sidebar, content, TOC rail,
footer. The content area calls domify() on each AST node via DomifyContext.
=#

import Documenter
import MarkdownAST

"""
    render_page(doc, settings, page, nav_ctx, light_scheme, dark_scheme)

Render a single documentation page to an HTML file in the build directory.
"""
function render_page(doc::Documenter.Document, settings::Material3,
                     page::Documenter.Page, nav_ctx::NavContext,
                     light_scheme::Dict{Symbol,String},
                     dark_scheme::Dict{Symbol,String})
    io = IOBuffer()

    # Compute page metadata
    page_title = _page_title_from_page(page)
    sitename = doc.user.sitename
    root_dir = doc.user.root

    # page.build is like "build/api.md" (relative to root, with .md extension)
    # We need to: change .md → .html, and optionally apply prettyurls
    page_build_html = replace(page.build, r"\.md$" => ".html")

    # Get the portion after the build dir prefix for relative path calculations
    build_prefix = doc.user.build * (Sys.iswindows() ? "\\" : "/")
    page_rel = startswith(page_build_html, build_prefix) ?
        page_build_html[length(build_prefix)+1:end] : page_build_html

    if settings.prettyurls && page_rel != "index.html"
        # "api.html" → "api/index.html"
        out_name = replace(page_rel, r"\.html$" => "")
        out_file = joinpath(root_dir, doc.user.build, out_name, "index.html")
        root_prefix = _relative_root(out_name * "/index.html")
    else
        out_file = joinpath(root_dir, doc.user.build, page_rel)
        root_prefix = _relative_root(page_rel)
    end
    out_dir = dirname(out_file)
    isdir(out_dir) || mkpath(out_dir)

    # Generate Google Fonts link
    fonts_link = _google_fonts_link(settings.theme)

    # Determine data-theme attribute
    theme_attr = if settings.dark_mode == :light
        " data-theme=\"light\""
    elseif settings.dark_mode == :dark
        " data-theme=\"dark\""
    else
        ""
    end

    # ── HTML Head ──
    print(io, """
    <!doctype html>
    <html lang="en"$theme_attr>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>$page_title — $sitename</title>
      <link rel="stylesheet" href="$(root_prefix)assets/materialdocs.css">
      $fonts_link
    """)

    # Favicon
    if settings.favicon !== nothing
        fav_name = basename(settings.favicon)
        println(io, "  <link rel=\"icon\" href=\"$(root_prefix)assets/$fav_name\">")
    end

    # Custom CSS
    for css in settings.custom_css
        println(io, "  <link rel=\"stylesheet\" href=\"$(root_prefix)assets/$(basename(css))\">")
    end

    println(io, "</head>")
    println(io, "<body>")

    # ── Navbar ──
    print(io, """
      <header class="md-navbar">
    """)
    if settings.logo !== nothing
        logo_name = basename(settings.logo)
        println(io, "    <img class=\"md-navbar-logo\" src=\"$(root_prefix)assets/$logo_name\" alt=\"$sitename logo\" height=\"32\">")
    end
    println(io, "    <span class=\"md-navbar-title\">$sitename</span>")
    println(io, "    <span style=\"flex:1\"></span>")

    # Theme toggle button
    if settings.dark_mode == :toggle
        println(io, "    <button id=\"md-theme-toggle\" class=\"md-icon-btn\" title=\"Toggle dark mode\" aria-label=\"Toggle dark mode\">🌓</button>")
    end

    println(io, "  </header>")

    # ── Layout grid ──
    println(io, "  <div class=\"md-layout\">")

    # ── Sidebar ──
    println(io, "    <nav class=\"md-sidebar\">")
    _render_nav(io, nav_ctx, page.build, root_prefix, settings)
    println(io, "    </nav>")

    # ── Main content ──
    println(io, "    <main class=\"md-content\">")
    println(io, "      <article class=\"md-article\">")

    # Render page content via domify dispatch
    _render_article_content(io, page, doc, root_prefix, settings)

    println(io, "      </article>")
    println(io, "    </main>")

    # ── TOC rail ──
    println(io, "    <aside class=\"md-toc\">")
    _render_toc(io, page, settings.toc_depth)
    println(io, "    </aside>")

    println(io, "  </div>")  # md-layout

    # ── Footer ──
    println(io, "  <footer class=\"md-footer\">")
    if settings.footer !== nothing
        println(io, "    <p>", settings.footer, "</p>")
    end
    println(io, "    <p>Built with <a href=\"https://github.com/JuliaDocs/Documenter.jl\">Documenter.jl</a> and <a href=\"https://github.com/mthelm85/MaterialDocs.jl\">MaterialDocs.jl</a></p>")
    println(io, "  </footer>")

    # ── JS ──
    println(io, "  <script src=\"$(root_prefix)assets/materialdocs.js\"></script>")
    for js in settings.custom_js
        println(io, "  <script src=\"$(root_prefix)assets/$(basename(js))\"></script>")
    end

    println(io, "</body>")
    println(io, "</html>")

    # Write the file
    Base.write(out_file, String(take!(io)))
end

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""Extract page title from the page's AST (first H1) or filename."""
function _page_title_from_page(page::Documenter.Page)::String
    mdast = page.mdast
    for child in mdast.children
        heading_node, _ = _extract_heading(child)
        if heading_node !== nothing && heading_node.element.level == 1
            return _collect_text(heading_node)
        end
    end
    name = splitext(basename(page.build))[1]
    replace(titlecase(name), '-' => ' ', '_' => ' ')
end

"""
    _extract_heading(node) → (heading_node, slug) or (nothing, "")

Extract the heading node and its slug from a top-level AST node.
Handles both bare `MarkdownAST.Heading` nodes and Documenter's
`AnchoredHeader` wrapper.
"""
function _extract_heading(node)
    elem = node.element
    if elem isa MarkdownAST.Heading
        text = _collect_text(node)
        return (node, _slugify(text))
    elseif elem isa Documenter.AnchoredHeader
        slug = Documenter.anchor_label(elem.anchor)
        # Find the Heading child inside the AnchoredHeader
        for child in node.children
            if child.element isa MarkdownAST.Heading
                return (child, slug)
            end
        end
    end
    return (nothing, "")
end

"""Compute relative path prefix to reach the build root from a page path."""
function _relative_root(page_rel::String)::String
    # Count directory separators to determine depth
    normalized = replace(page_rel, '\\' => '/')
    depth = count('/', normalized)
    depth == 0 ? "./" : repeat("../", depth)
end

"""Generate a Google Fonts <link> tag from theme configuration."""
function _google_fonts_link(theme::ThemeConfig)::String
    # Collect unique font families
    families = String[]
    _add_font!(families, theme.display_font, "400;500;600;700")
    if theme.body_font != theme.display_font
        _add_font!(families, theme.body_font, "400;500;600;700")
    end
    _add_font!(families, theme.code_font, "400;500")

    if isempty(families)
        return ""
    end

    params = join(families, "&")
    "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?$params&display=swap\">"
end

function _add_font!(families::Vector{String}, name::AbstractString, weights::String)
    encoded = replace(name, ' ' => '+')
    push!(families, "family=$encoded:wght@$weights")
end

"""Render sidebar navigation links."""
function _render_nav(io::IO, nav_ctx::NavContext, current_page::String,
                     root_prefix::String, settings::Material3)
    for item in nav_ctx.items
        _render_nav_item(io, item, current_page, root_prefix, 0, settings)
    end
end

function _render_nav_item(io::IO, item::NavItem, current_page::String,
                          root_prefix::String, depth::Int,
                          settings::Material3)
    item.visible || return

    indent = "      " * repeat("  ", depth)

    if item.path !== nothing
        is_active = item.path == current_page
        active_class = is_active ? " class=\"md-nav-active\"" : ""
        href = root_prefix * _nav_href(item.path, settings.prettyurls)
        println(io, indent, "<a href=\"", href, "\"", active_class, ">", _html_escape(item.title), "</a>")
    elseif !isempty(item.children)
        # Section header
        println(io, indent, "<div class=\"md-nav-section\">")
        println(io, indent, "  <span class=\"md-nav-section-title\">", _html_escape(item.title), "</span>")
    end

    if !isempty(item.children)
        for child in item.children
            _render_nav_item(io, child, current_page, root_prefix, depth + 1, settings)
        end
        if item.path === nothing
            println(io, indent, "</div>")
        end
    end
end

"""Render right-rail table of contents from page headings."""
function _render_toc(io::IO, page::Documenter.Page, max_depth::Int)
    println(io, "      <div class=\"md-toc-inner\">")
    println(io, "        <p class=\"md-toc-title\">On this page</p>")

    mdast = page.mdast
    for child in mdast.children
        heading_node, slug = _extract_heading(child)
        heading_node === nothing && continue
        level = heading_node.element.level
        (level < 2 || level > max_depth) && continue
        text = _collect_text(heading_node)
        indent = repeat("  ", level - 1)
        println(io, "        $indent<a class=\"md-toc-link md-toc-h$level\" href=\"#$(_html_escape(slug))\">", _html_escape(text), "</a>")
    end

    println(io, "      </div>")
end

"""Render article content from page AST via domify dispatch."""
function _render_article_content(io::IO, page::Documenter.Page,
                                 doc::Documenter.Document, root_prefix::String,
                                 settings::Material3)
    buf = IOBuffer()
    ctx = DomifyContext(buf, doc, page, root_prefix, settings)
    domify(ctx, page.mdast)
    write(io, take!(buf))
end


# NOTE: AST → HTML dispatch is handled by domify.jl (DomifyContext + domify methods).

# ─────────────────────────────────────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────────────────────────────────────

"""Convert a nav item page path (e.g. `"api.md"`) to an HTML href."""
function _nav_href(page_path::String, prettyurls::Bool)::String
    html_path = replace(page_path, r"\.md$" => ".html")
    if prettyurls
        if html_path == "index.html"
            return ""
        else
            # "api.html" → "api/"
            return replace(html_path, r"\.html$" => "") * "/"
        end
    else
        return html_path
    end
end

"""Escape HTML special characters."""
function _html_escape(s::AbstractString)::String
    replace(s,
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&#39;",
    )
end

"""Generate a URL-safe slug from heading text."""
function _slugify(text::AbstractString)::String
    s = lowercase(text)
    s = replace(s, r"[^\w\s-]" => "")
    s = replace(s, r"[\s_]+" => "-")
    s = strip(s, '-')
    s
end
