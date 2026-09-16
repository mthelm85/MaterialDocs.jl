#=
Page — renders individual documentation pages to HTML files.

Generates the full HTML document: head, navbar, sidebar, content, TOC rail,
footer. The content area calls domify() on each AST node via DomifyContext.
=#

import Documenter
import MarkdownAST

"""
    render_page(doc, settings, page, nav_ctx, light_scheme, dark_scheme; state)

Render a single documentation page to an HTML file in the build directory.
`state` is shared across a build's pages so unsupported elements warn once.
"""
function render_page(doc::Documenter.Document, settings::Material3,
                     page::Documenter.Page, nav_ctx::NavContext,
                     light_scheme::Dict{Symbol,String},
                     dark_scheme::Dict{Symbol,String};
                     state::RenderState = RenderState())
    io = IOBuffer()

    # Compute page metadata
    page_title = _page_title_from_page(page)
    sitename = doc.user.sitename
    root_dir = doc.user.root

    # page.build is like "build/api.md" (relative to root, with .md extension)
    # We need to: change .md → .html, and optionally apply prettyurls
    page_build_html = replace(page.build, r"\.md$" => ".html")

    # Get the portion after the build dir prefix for relative path calculations
    # Normalize separators to "/" for consistent matching across platforms
    _norm(p) = replace(p, '\\' => '/')
    build_prefix = _norm(doc.user.build) * "/"
    page_build_norm = _norm(page_build_html)
    page_rel = startswith(page_build_norm, build_prefix) ?
        page_build_norm[length(build_prefix)+1:end] : page_build_norm

    if settings.html.prettyurls && page_rel != "index.html"
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

    # Cache-busting hash based on build time
    _cache_v = string(hash(time()), base=16)[1:8]

    html = settings.html
    full_title = "$page_title — $sitename"

    # ── HTML Head ──
    print(io, """
    <!doctype html>
    <html lang="$(_html_escape(html.lang))"$theme_attr>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>$full_title</title>
      <link rel="stylesheet" href="$(root_prefix)assets/materialdocs.css?v=$(_cache_v)">
      $fonts_link
    """)

    _render_head_metadata(io, doc, settings, page, full_title)

    # Favicon
    if settings.favicon !== nothing
        fav_name = basename(settings.favicon)
        println(io, "  <link rel=\"icon\" href=\"$(root_prefix)assets/$fav_name\">")
    end

    # User assets, in the order given — after our stylesheet so they can override it
    _render_assets(io, html.assets, root_prefix)

    # Inline script to prevent FOUC: restore theme + suppress transitions during load
    println(io, "  <script>")
    println(io, "    (function(){")
    println(io, "      document.documentElement.classList.add('no-transition');")
    if settings.dark_mode == :toggle
        println(io, "      var t=localStorage.getItem('md-theme');if(t)document.documentElement.setAttribute('data-theme',t);")
    end
    println(io, "      window.addEventListener('load',function(){setTimeout(function(){document.documentElement.classList.remove('no-transition');},50);});")
    println(io, "    })()")
    println(io, "  </script>")

    println(io, "</head>")
    println(io, html.warn_outdated ? "<body data-warn-outdated>" : "<body>")

    # ── Navbar ──
    println(io, "  <header class=\"md-navbar\">")

    # Hamburger menu (mobile)
    println(io, "    <button id=\"md-hamburger\" class=\"md-icon-btn md-hamburger\" aria-label=\"Toggle navigation\" aria-expanded=\"false\">",
                _icon(:menu), "</button>")

    _render_logo(io, doc, settings, root_prefix)
    if html.sidebar_sitename
        println(io, "    <span class=\"md-navbar-title\">$(_html_escape(sitename))</span>")
    end
    println(io, "    <span class=\"md-navbar-spacer\"></span>")

    # ── MD3 search bar — morphs into a search view on activation ──
    if settings.search
        println(io, "    <button id=\"md-search-btn\" class=\"md-search-bar\" aria-label=\"Search documentation\" aria-expanded=\"false\">")
        println(io, "      ", _icon(:search, "md-search-bar-icon"))
        println(io, "      <span class=\"md-search-bar-label\">Search docs</span>")
        println(io, "      <kbd class=\"md-search-bar-kbd\">Ctrl K</kbd>")
        println(io, "    </button>")
    end

    # ── Version selector — populated by versions.js, hidden until then ──
    if settings.versions
        println(io, "    <div id=\"md-version\" class=\"md-version\" hidden>")
        println(io, "      <button id=\"md-version-btn\" class=\"md-version-btn\" aria-haspopup=\"listbox\" aria-expanded=\"false\" aria-label=\"Select documentation version\">")
        println(io, "        <span id=\"md-version-current\" class=\"md-version-current\"></span>")
        println(io, "        ", _icon(:arrow_drop_down, "md-version-caret"))
        println(io, "      </button>")
        println(io, "      <ul id=\"md-version-menu\" class=\"md-version-menu\" role=\"listbox\" hidden></ul>")
        println(io, "    </div>")
    end

    # ── Repository link ──
    repo = _repo_link(doc, settings)
    if repo !== nothing
        url, host = repo
        label = isempty(host) ? "Repository" : host
        println(io, "    <a class=\"md-icon-btn md-repo-link\" href=\"$(_html_escape(url))\" ",
                    "title=\"View the repository", isempty(host) ? "" : " on $host", "\" ",
                    "aria-label=\"View the repository", isempty(host) ? "" : " on $host", "\" ",
                    "rel=\"noopener\" target=\"_blank\">",
                    _icon(_repo_icon(host)),
                    "<span class=\"md-repo-label\">$(_html_escape(label))</span></a>")
    end

    # Theme toggle button
    if settings.dark_mode == :toggle
        println(io, "    <button id=\"md-theme-toggle\" class=\"md-icon-btn\" title=\"Toggle dark mode\" aria-label=\"Toggle dark mode\">",
                    _icon(:light_mode, "md-icon-light"), _icon(:dark_mode, "md-icon-dark"), "</button>")
    end

    println(io, "  </header>")

    # ── Layout grid ──
    # Hide sidebar when there's only one page (no useful navigation)
    hide_sidebar = _nav_leaf_count(nav_ctx) <= 1
    if hide_sidebar
        println(io, "  <div class=\"md-layout md-layout-no-sidebar\">")

        # TOC on the left (takes the sidebar's place)
        println(io, "    <aside class=\"md-toc\">")
        _render_toc(io, page, settings.toc_depth)
        println(io, "    </aside>")
    else
        println(io, "  <div class=\"md-layout\">")

        # ── Sidebar ──
        println(io, "    <nav class=\"md-sidebar\">")
        # Nav items hold source paths relative to docs/src ("guide/intro.md")
        current_src = _normpath(relpath(page.source, doc.user.source))
        _render_nav(io, nav_ctx, current_src, root_prefix, settings)
        println(io, "    </nav>")
    end

    # ── Main content ──
    println(io, "    <main class=\"md-content\">")
    println(io, "      <article class=\"md-article\">")

    edit = _edit_link(doc, settings, page)
    if edit !== nothing
        verb_title, url, icon = edit
        println(io, "      <div class=\"md-article-actions\"><a class=\"md-icon-btn md-edit-link\" href=\"",
                _html_escape(url), "\" title=\"", _html_escape(verb_title), "\" aria-label=\"",
                _html_escape(verb_title), "\">", _icon(icon), "</a></div>")
    end

    # Render page content via domify dispatch
    _render_article_content(io, page, doc, root_prefix, settings, state)

    println(io, "      </article>")


    # Footer inside content column so it scrolls with the article
    println(io, "      <footer class=\"md-footer\">")
    if html.footer !== nothing
        footer_ctx = DomifyContext(IOBuffer(), doc, page, root_prefix, settings, state)
        domify(footer_ctx, html.footer)
        write(io, take!(footer_ctx.io))
    end
    println(io, "      </footer>")

    println(io, "    </main>")

    if !hide_sidebar
        # ── TOC rail (right side, only for multi-page sites) ──
        println(io, "    <aside class=\"md-toc\">")
        _render_toc(io, page, settings.toc_depth)
        println(io, "    </aside>")
    end

    println(io, "  </div>")  # md-layout

    # ── JS ──
    # Syntax highlighting (highlight.js CDN + Julia language packs)
    println(io, "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js\"></script>")
    println(io, "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/julia.min.js\"></script>")
    println(io, "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/julia-repl.min.js\"></script>")
    for lang in html.highlights
        println(io, "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/$(_html_escape(lang)).min.js\"></script>")
    end
    println(io, "  <script>hljs.highlightAll();</script>")

    # Math typesetting, only on pages that contain math. Each element holds
    # its TeX between \( \) or \[ \] delimiters, readable if KaTeX never loads.
    if state.math
        print(io, _math_scripts(html.mathengine))
    end

    # Version metadata written by Documenter's deploydocs(), read by the version
    # selector and the outdated banner. Absent on local builds — both guard on
    # `typeof`, so a 404 here is harmless.
    if settings.versions || html.warn_outdated
        println(io, "  <script src=\"$(root_prefix)siteinfo.js\"></script>")
        println(io, "  <script src=\"$(root_prefix)../versions.js\"></script>")
    end

    println(io, "  <script src=\"$(root_prefix)assets/materialdocs.js?v=$(_cache_v)\"></script>")

    println(io, "</body>")
    println(io, "</html>")

    # Write the file
    bytes = take!(io)
    Base.write(out_file, bytes)
    return _check_page_size(settings, _normpath(relpath(page.source, doc.user.source)),
                            length(bytes), out_file)
end

"""
    _check_page_size(settings, src, nbytes, path) → Bool

Apply Documenter.HTML's page size limits: log a warning over
`size_threshold_warn`, an error over `size_threshold` (returning `false` so the
build fails), and nothing for pages in `size_threshold_ignore`.
"""
function _check_page_size(settings::Material3, src::AbstractString, nbytes::Integer,
                          path::AbstractString)
    html = settings.html
    fmt = Documenter.HTMLWriter.format_units
    msg(var) = """
    Generated HTML over $(var) limit: $src
        Generated file size: $(fmt(nbytes))
        size_threshold_warn: $(fmt(html.size_threshold_warn))
        size_threshold:      $(fmt(html.size_threshold))
        HTML file:           $path"""
    if src in _normpath.(html.size_threshold_ignore)
        return true
    elseif nbytes > html.size_threshold
        @error msg(:size_threshold)
        return false
    elseif nbytes > html.size_threshold_warn
        @warn msg(:size_threshold_warn)
    end
    return true
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
        is_active = _normpath(item.path) == current_page
        active_class = is_active ? " class=\"md-nav-active\"" : ""
        href = root_prefix * _nav_href(item.path, settings.html.prettyurls)
        println(io, indent, "<a href=\"", href, "\"", active_class, ">", _html_escape(item.title), "</a>")
    elseif !isempty(item.children)
        # Section header. As in Documenter, sections at level `collapselevel`
        # or deeper start collapsed unless they lead to the current page.
        collapsed = depth + 1 >= settings.html.collapselevel &&
                    !_nav_contains(item, current_page)
        println(io, indent, "<div class=\"md-nav-section", collapsed ? " md-nav-collapsed" : "", "\">")
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
                                 settings::Material3,
                                 state::RenderState = RenderState())
    buf = IOBuffer()
    state.math = false
    ctx = DomifyContext(buf, doc, page, root_prefix, settings, state)
    domify(ctx, page.mdast)
    write(io, take!(buf))
end

const KATEX_VERSION = "0.18.6"
const MATHJAX2_URL = "https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.9/MathJax.js?config=TeX-AMS_HTML"
const MATHJAX3_URL = "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg-full.js"

# Options of KaTeX's auto-render extension. MaterialDocs renders each math
# element directly, so these don't apply; everything else is a render option.
const KATEX_AUTORENDER_KEYS = (:delimiters, :ignoredTags, :ignoredClasses, :errorCallback, :preProcess)

# `el` holds its TeX between \( \) or \[ \], readable if the engine never loads
const KATEX_RENDER_JS = raw"""
document.querySelectorAll('.md-math').forEach(function (el) {
  var tex = el.textContent.trim().replace(/^\\[\[(]/, '').replace(/\\[\])]$/, '');
  katex.render(tex, el, Object.assign({ throwOnError: false }, MD_KATEX_OPTIONS,
    { displayMode: el.classList.contains('md-math-display') }));
});"""

"""JSON for an inline <script>, with `</` escaped so it can't end the element."""
_script_json(x) = replace(Documenter.JSDependencies.json_jsescape(x), "</" => "<\\/")

"""
    _math_scripts(engine) → String

The tags that load and configure `mathengine`, mirroring Documenter.HTML:
KaTeX with the render options from its config, MathJax 2 or 3 with their config
and `url`, or nothing.
"""
_math_scripts(::Nothing) = ""

function _math_scripts(engine::Documenter.KaTeX)
    options = Dict(k => v for (k, v) in engine.config if !(k in KATEX_AUTORENDER_KEYS))
    base = "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/$(KATEX_VERSION)"
    string("  <link rel=\"stylesheet\" href=\"$base/katex.min.css\">\n",
           "  <script src=\"$base/katex.min.js\"></script>\n",
           "  <script>var MD_KATEX_OPTIONS = ", _script_json(options), ";\n", KATEX_RENDER_JS, "</script>\n")
end

function _math_scripts(engine::Documenter.MathJax2)
    url = isempty(engine.url) ? MATHJAX2_URL : engine.url
    string("  <script type=\"text/x-mathjax-config\">MathJax.Hub.Config(", _script_json(engine.config), ");</script>\n",
           "  <script src=\"", _html_escape(url), "\"></script>\n")
end

function _math_scripts(engine::Documenter.MathJax3)
    url = isempty(engine.url) ? MATHJAX3_URL : engine.url
    string("  <script>window.MathJax = ", _script_json(engine.config), ";</script>\n",
           "  <script src=\"", _html_escape(url), "\" async></script>\n")
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

# ─────────────────────────────────────────────────────────────────────────────
# Icons — inline SVG (Material Symbols paths, 24×24 viewBox)
# ─────────────────────────────────────────────────────────────────────────────

const ICON_PATHS = Dict{Symbol,String}(
    :menu => "M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z",
    :search => "M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
    :close => "M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
    :arrow_back => "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
    :arrow_drop_down => "M7 10l5 5 5-5z",
    :edit => "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a.996.996 0 000-1.41l-2.34-2.34a.996.996 0 00-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z",
    :code => "M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z",
    :check => "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
    :light_mode => "M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58a.996.996 0 00-1.41 0 .996.996 0 000 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37a.996.996 0 00-1.41 0 .996.996 0 000 1.41l1.06 1.06c.39.39 1.03.39 1.41 0a.996.996 0 000-1.41l-1.06-1.06zm1.06-10.96a.996.996 0 000-1.41.996.996 0 00-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06zM7.05 18.36a.996.996 0 000-1.41.996.996 0 00-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06z",
    :dark_mode => "M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9c0-.46-.04-.92-.1-1.36-.98 1.37-2.58 2.26-4.4 2.26-2.98 0-5.4-2.42-5.4-5.4 0-1.81.89-3.42 2.26-4.4-.44-.06-.9-.1-1.36-.1z",
    :github => "M12 .3a12 12 0 00-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 0-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.3-3.1-.2-.4-.6-1.6.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 016 0c2.3-1.5 3.3-1.2 3.3-1.2.7 1.6.2 2.8.1 3.2.8.8 1.3 1.9 1.3 3.2 0 4.6-2.8 5.6-5.5 5.9.5.4.9 1.1.9 2.2v3.3c0 .3.1.7.8.6A12 12 0 0012 .3z",
    :gitlab => "M22.65 14.39L12 22.13 1.35 14.39a.84.84 0 01-.3-.94l1.22-3.78 2.44-7.51A.42.42 0 014.82 2a.43.43 0 01.58.18l2.44 7.49h8.32l2.44-7.51A.42.42 0 0119 2a.43.43 0 01.58.18l2.44 7.51L23.2 13.4a.84.84 0 01-.55.99z",
    :git => "M23.5 11.1l-10.6-10.6a1.4 1.4 0 00-2 0L8.7 2.7l2.8 2.8a1.7 1.7 0 012.1 2.1l2.7 2.7a1.7 1.7 0 11-1 1l-2.5-2.5v6.6a1.7 1.7 0 11-1.4 0V8.8a1.7 1.7 0 01-.9-2.2L7.7 3.8.5 11a1.4 1.4 0 000 2l10.6 10.6a1.4 1.4 0 002 0l10.4-10.4a1.4 1.4 0 000-2z",
)

"""Render an inline SVG icon by name, with an optional extra CSS class."""
function _icon(name::Symbol, extra_class::AbstractString = "")::String
    path = get(ICON_PATHS, name, ICON_PATHS[:git])
    cls = isempty(extra_class) ? "md-icon" : "md-icon $extra_class"
    string("<svg class=\"", cls, "\" viewBox=\"0 0 24 24\" width=\"20\" height=\"20\" ",
           "fill=\"currentColor\" aria-hidden=\"true\" focusable=\"false\">",
           "<path d=\"", path, "\"/></svg>")
end

# ─────────────────────────────────────────────────────────────────────────────
# Repository link
# ─────────────────────────────────────────────────────────────────────────────

"""
    _repo_root_from_template(template) → String or nothing

Recover a repository root from a Documenter source-URL template.

Documenter turns `repo = "https://host/o/r/blob/{commit}{path}#{line}"` into a
`Remotes.URL`, whose `repourl` is `nothing` — so the navbar link would be
dropped even though the URL is right there. BestieTemplate generates precisely
that form, so truncate the template at the host's source-path marker instead.
Returns `nothing` when no marker is recognised, since a wrong link is worse
than none.
"""
function _repo_root_from_template(template::AbstractString)
    isempty(template) && return nothing
    # Take the earliest marker, not the first in list order: GitLab's "/-/blob/"
    # contains "/blob/", so scanning in order would truncate one segment late.
    cut = nothing
    for marker in ("/blob/", "/-/", "/src/", "/tree/")
        i = findfirst(marker, template)
        i === nothing && continue
        cut = cut === nothing ? first(i) : min(cut, first(i))
    end
    cut === nothing && return nothing
    root = template[1:prevind(template, cut)]
    isempty(root) ? nothing : String(root)
end

"""
    _repo_link(doc, settings) → (url, host) or nothing

Resolve the source-repository URL for the navbar link. Honours an explicit
`repolink` string, `nothing` to disable, or (when unset) derives the URL from
Documenter's configured remote.
"""
function _repo_link(doc::Documenter.Document, settings::Material3)
    repolink = settings.html.repolink
    repolink === nothing && return nothing

    url = if repolink isa String
        repolink
    else  # unset — derive from the Documenter remote
        remote = doc.user.remote
        remote === nothing && return nothing
        derived = try
            Documenter.Remotes.repourl(remote)
        catch
            nothing
        end
        # A Remotes.URL built from a template has no repourl; recover it.
        if derived === nothing && hasproperty(remote, :urltemplate)
            derived = _repo_root_from_template(remote.urltemplate)
        end
        derived
    end

    (url === nothing || isempty(url)) && return nothing
    (url, _repo_host(url))
end

"""Identify the hosting service from a repository URL."""
function _repo_host(url::AbstractString)::String
    u = lowercase(url)
    occursin("github", u)    ? "GitHub"    :
    occursin("gitlab", u)    ? "GitLab"    :
    occursin("bitbucket", u) ? "Bitbucket" :
    occursin("azure", u)     ? "Azure DevOps" : ""
end

"""Pick the icon matching a repository host name."""
function _repo_icon(host::AbstractString)::Symbol
    host == "GitHub" ? :github :
    host == "GitLab" ? :gitlab : :git
end

"""Whether `item` or any of its descendants is the page at `path`."""
_nav_contains(item::NavItem, path::AbstractString) =
    (item.path !== nothing && _normpath(item.path) == path) ||
    any(child -> _nav_contains(child, path), item.children)

"""A path with forward slashes, so Windows and POSIX paths compare equal."""
_normpath(path::AbstractString) = replace(path, '\\' => '/')

"""Count visible leaf pages in the nav context."""
function _nav_leaf_count(nav_ctx::NavContext)::Int
    count = 0
    for item in nav_ctx.items
        count += _count_leaves(item)
    end
    count
end

function _count_leaves(item::NavItem)::Int
    item.visible || return 0
    if item.path !== nothing
        n = 1
    else
        n = 0
    end
    for child in item.children
        n += _count_leaves(child)
    end
    n
end

"""Generate a URL-safe slug from heading text."""
function _slugify(text::AbstractString)::String
    s = lowercase(text)
    s = replace(s, r"[^\w\s-]" => "")
    s = replace(s, r"[\s_]+" => "-")
    s = strip(s, '-')
    s
end

# ─────────────────────────────────────────────────────────────────────────────
# Documenter.HTML head options
# ─────────────────────────────────────────────────────────────────────────────

"""
Description, canonical-URL, preview-image and analytics tags, matching the ones
Documenter.HTML writes.
"""
function _render_head_metadata(io::IO, doc::Documenter.Document, settings::Material3,
                               page::Documenter.Page, full_title::AbstractString)
    html = settings.html
    esc = _html_escape
    default_description = something(html.description, "Documentation for $(doc.user.sitename).")
    description = string(get(page.globals.meta, :Description, default_description))

    println(io, "  <meta name=\"title\" content=\"", esc(full_title), "\">")
    println(io, "  <meta property=\"og:title\" content=\"", esc(full_title), "\">")
    println(io, "  <meta property=\"twitter:title\" content=\"", esc(full_title), "\">")
    println(io, "  <meta name=\"description\" content=\"", esc(description), "\">")
    println(io, "  <meta property=\"og:description\" content=\"", esc(description), "\">")
    println(io, "  <meta property=\"twitter:description\" content=\"", esc(description), "\">")

    if html.canonical !== nothing
        base = rstrip(html.canonical, '/')
        src = replace(relpath(page.source, doc.user.source), '\\' => '/')
        url = "$base/" * _pretty_url(settings, _page_url(settings, src))
        println(io, "  <meta property=\"og:url\" content=\"", esc(url), "\">")
        println(io, "  <meta property=\"twitter:url\" content=\"", esc(url), "\">")
        println(io, "  <link rel=\"canonical\" href=\"", esc(url), "\">")

        preview = _find_build_asset(doc, "preview", ("png", "webp", "gif", "jpg", "jpeg"))
        if preview !== nothing
            image = "$base/$preview"
            println(io, "  <meta property=\"og:image\" content=\"", esc(image), "\">")
            println(io, "  <meta property=\"twitter:image\" content=\"", esc(image), "\">")
            println(io, "  <meta property=\"twitter:card\" content=\"summary_large_image\">")
        end
    end

    if !isempty(html.analytics)
        id = esc(html.analytics)
        println(io, "  <script async src=\"https://www.googletagmanager.com/gtag/js?id=$id\"></script>")
        println(io, """
          <script>
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', '$id', {'page_path': location.pathname + location.search + location.hash});
          </script>""")
    end
end

"""Link `assets` entries: local files relative to the site root, remote URLs and raw HTML verbatim."""
function _render_assets(io::IO, assets, root_prefix::AbstractString)
    for a in assets
        if a isa Documenter.HTMLWriter.RawHTMLHeadContent
            println(io, "  ", a.content)
            continue
        end
        a isa Documenter.HTMLWriter.HTMLAsset || continue
        url = _html_escape(a.islocal ? root_prefix * a.uri : a.uri)
        attrs = join(" $(k)=\"$(_html_escape(v))\"" for (k, v) in sort(collect(a.attributes)))
        if a.class === :css
            println(io, "  <link rel=\"stylesheet\" href=\"$url\"$attrs>")
        elseif a.class === :js
            println(io, "  <script src=\"$url\"$attrs></script>")
        elseif a.class === :ico
            println(io, "  <link rel=\"icon\" type=\"image/x-icon\" href=\"$url\"$attrs>")
        end
    end
end

"""
The navbar logo: the `logo` keyword, else `assets/logo.*` as Documenter finds it,
with `assets/logo-dark.*` swapped in for dark mode when present.
"""
function _render_logo(io::IO, doc::Documenter.Document, settings::Material3,
                      root_prefix::AbstractString)
    alt = _html_escape("$(doc.user.sitename) logo")
    if settings.logo !== nothing
        src = "$(root_prefix)assets/$(basename(settings.logo))"
        println(io, "    <img class=\"md-navbar-logo\" src=\"$src\" alt=\"$alt\" height=\"32\">")
        return
    end
    exts = ("svg", "png", "webp", "gif", "jpg", "jpeg")
    light = _find_build_asset(doc, "logo", exts)
    light === nothing && return
    dark = _find_build_asset(doc, "logo-dark", exts)
    if dark === nothing
        println(io, "    <img class=\"md-navbar-logo\" src=\"$(root_prefix)$light\" alt=\"$alt\" height=\"32\">")
    else
        println(io, "    <img class=\"md-navbar-logo md-logo-light\" src=\"$(root_prefix)$light\" alt=\"$alt\" height=\"32\">")
        println(io, "    <img class=\"md-navbar-logo md-logo-dark\" src=\"$(root_prefix)$dark\" alt=\"$alt\" height=\"32\">")
    end
end

"""The first `assets/<name>.<ext>` present in the build, as a site-relative path."""
function _find_build_asset(doc::Documenter.Document, name::AbstractString, exts)
    for ext in exts
        rel = "assets/$name.$ext"
        isfile(joinpath(doc.user.root, doc.user.build, rel)) && return rel
    end
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Edit link and previous/next navigation
# ─────────────────────────────────────────────────────────────────────────────

"""
    _edit_link(doc, settings, page) → (title, url, icon) or nothing

The page's source link, following Documenter.HTML's rules: an absolute
`@meta EditURL` is used as-is ("View source"); otherwise the source file is
linked on the remote at `edit_link` ("Edit source"), or at the current commit
for `edit_link = :commit` ("View source"), unless `edit_link = nothing` or
`disable_git = true`.
"""
function _edit_link(doc::Documenter.Document, settings::Material3, page::Documenter.Page)
    html = settings.html
    editpath = get(page.globals.meta, :EditURL, page.source)
    editpath === nothing && return nothing
    editpath = string(editpath)
    if Documenter.isabsurl(editpath)
        host = _repo_host(editpath)
        return ("View source" * (isempty(host) ? "" : " on $host"), editpath, :code)
    end
    (html.disable_git || html.edit_link === nothing) && return nothing
    # A relative EditURL is relative to the page, while page.source is relative to the root
    editpath == page.source || (editpath = joinpath(dirname(page.source), editpath))
    verb, icon, rev = html.edit_link === :commit ? ("View", :code, nothing) :
                                                    ("Edit", :edit, string(html.edit_link))
    url = Documenter.edit_url(doc, editpath; rev)
    url === nothing && return nothing
    host = _repo_host(url)
    return ("$verb source" * (isempty(host) ? "" : " on $host"), url, icon)
end
