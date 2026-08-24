#=
Page — renders individual documentation pages to HTML files.

Generates the full HTML document: head, navbar, sidebar, content, TOC rail,
footer. The content area calls domify() on each AST node (Phase 3).
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
    build_dir = doc.user.build

    # Determine output path
    if settings.prettyurls && page.build != "index.html"
        # page.build is like "page.html" → write to "page/index.html"
        out_name = replace(page.build, r"\.html$" => "")
        out_dir = joinpath(build_dir, out_name)
        out_file = joinpath(out_dir, "index.html")
        root_prefix = _relative_root(out_name)
    else
        out_dir = build_dir
        out_file = joinpath(build_dir, page.build)
        root_prefix = _relative_root(page.build)
    end
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

    # Render page content — domify dispatch (scaffold for Phase 3)
    _render_article_content(io, page, doc, root_prefix)

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
        if child.element isa MarkdownAST.Heading && child.element.level == 1
            return _collect_text(child)
        end
    end
    name = splitext(basename(page.build))[1]
    replace(titlecase(name), '-' => ' ', '_' => ' ')
end

"""Compute relative path prefix to reach the root from a page path."""
function _relative_root(page_build::String)::String
    depth = count('/', replace(page_build, '\\' => '/'))
    depth == 0 ? "" : repeat("../", depth)
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
        _render_nav_item(io, item, current_page, root_prefix, 0)
    end
end

function _render_nav_item(io::IO, item::NavItem, current_page::String,
                          root_prefix::String, depth::Int)
    item.visible || return

    indent = "      " * repeat("  ", depth)

    if item.path !== nothing
        is_active = item.path == current_page
        active_class = is_active ? " class=\"md-nav-active\"" : ""
        href = root_prefix * item.path
        println(io, indent, "<a href=\"", href, "\"", active_class, ">", _html_escape(item.title), "</a>")
    elseif !isempty(item.children)
        # Section header
        println(io, indent, "<div class=\"md-nav-section\">")
        println(io, indent, "  <span class=\"md-nav-section-title\">", _html_escape(item.title), "</span>")
    end

    if !isempty(item.children)
        for child in item.children
            _render_nav_item(io, child, current_page, root_prefix, depth + 1)
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
        if child.element isa MarkdownAST.Heading
            level = child.element.level
            (level < 2 || level > max_depth) && continue
            text = _collect_text(child)
            slug = _slugify(text)
            indent = repeat("  ", level - 1)
            println(io, "        $indent<a class=\"md-toc-link md-toc-h$level\" href=\"#$slug\">", _html_escape(text), "</a>")
        end
    end

    println(io, "      </div>")
end

"""Render article content from page AST. Full domify dispatch in Phase 3."""
function _render_article_content(io::IO, page::Documenter.Page,
                                 doc::Documenter.Document, root_prefix::String)
    mdast = page.mdast
    for child in mdast.children
        _domify(io, child, doc, root_prefix)
    end
end

"""
    _domify(io, node, doc, root_prefix)

Render a single MarkdownAST node to HTML. This is the scaffold —
Phase 3 will implement full dispatch for all node types.
"""
function _domify(io::IO, node, doc::Documenter.Document, root_prefix::String)
    elem = node.element

    if elem isa MarkdownAST.Heading
        level = elem.level
        text = _collect_text(node)
        slug = _slugify(text)
        println(io, "        <h$level id=\"$slug\">", _html_escape(text), "</h$level>")

    elseif elem isa MarkdownAST.Paragraph
        print(io, "        <p>")
        for child in node.children
            _domify_inline(io, child, doc, root_prefix)
        end
        println(io, "</p>")

    elseif elem isa MarkdownAST.CodeBlock
        lang = elem.info
        lang_attr = isempty(lang) ? "" : " class=\"language-$lang\""
        println(io, "        <pre><code$lang_attr>", _html_escape(elem.code), "</code></pre>")

    elseif elem isa MarkdownAST.List
        tag = elem.type === :ordered ? "ol" : "ul"
        println(io, "        <$tag>")
        for child in node.children
            print(io, "          <li>")
            for li_child in child.children
                _domify(io, li_child, doc, root_prefix)
            end
            println(io, "</li>")
        end
        println(io, "        </$tag>")

    elseif elem isa MarkdownAST.BlockQuote
        println(io, "        <blockquote>")
        for child in node.children
            _domify(io, child, doc, root_prefix)
        end
        println(io, "        </blockquote>")

    elseif elem isa MarkdownAST.ThematicBreak
        println(io, "        <hr>")

    elseif elem isa MarkdownAST.HTMLBlock
        println(io, "        ", elem.html)

    elseif elem isa Documenter.DocsNode
        # API documentation block — render doc entries
        for docstr in elem.docstr
            println(io, "        <div class=\"md-docstring\">")
            println(io, "          <div class=\"md-docstring-binding\"><code>", _html_escape(string(elem.object.binding)), "</code></div>")
            # Render the docstring content
            for part in docstr.text
                if part isa MarkdownAST.Node
                    for child in part.children
                        _domify(io, child, doc, root_prefix)
                    end
                end
            end
            println(io, "        </div>")
        end

    elseif elem isa Documenter.AdmonitionNode || (hasproperty(elem, :category) && hasproperty(elem, :title))
        # Admonition blocks
        cat = hasproperty(elem, :category) ? elem.category : "note"
        title = hasproperty(elem, :title) ? elem.title : titlecase(cat)
        println(io, "        <div class=\"md-admonition md-admonition-$cat\">")
        println(io, "          <p class=\"md-admonition-title\">$title</p>")
        for child in node.children
            _domify(io, child, doc, root_prefix)
        end
        println(io, "        </div>")

    elseif elem isa MarkdownAST.Admonition
        println(io, "        <div class=\"md-admonition md-admonition-$(elem.category)\">")
        println(io, "          <p class=\"md-admonition-title\">", _html_escape(elem.title), "</p>")
        for child in node.children
            _domify(io, child, doc, root_prefix)
        end
        println(io, "        </div>")

    elseif elem isa MarkdownAST.TableComponent
        println(io, "        <div class=\"md-table-wrap\"><table>")
        for child in node.children
            _domify(io, child, doc, root_prefix)
        end
        println(io, "        </table></div>")

    else
        # Fallback: render children
        for child in node.children
            _domify(io, child, doc, root_prefix)
        end
    end
end

"""Render inline MarkdownAST nodes to HTML."""
function _domify_inline(io::IO, node, doc::Documenter.Document, root_prefix::String)
    elem = node.element

    if elem isa MarkdownAST.Text
        print(io, _html_escape(elem.text))
    elseif elem isa MarkdownAST.Code
        print(io, "<code>", _html_escape(elem.code), "</code>")
    elseif elem isa MarkdownAST.Emph
        print(io, "<em>")
        for child in node.children
            _domify_inline(io, child, doc, root_prefix)
        end
        print(io, "</em>")
    elseif elem isa MarkdownAST.Strong
        print(io, "<strong>")
        for child in node.children
            _domify_inline(io, child, doc, root_prefix)
        end
        print(io, "</strong>")
    elseif elem isa MarkdownAST.Link
        print(io, "<a href=\"", _html_escape(elem.destination), "\">")
        for child in node.children
            _domify_inline(io, child, doc, root_prefix)
        end
        print(io, "</a>")
    elseif elem isa MarkdownAST.Image
        print(io, "<img src=\"", _html_escape(elem.destination), "\" alt=\"", _html_escape(elem.description), "\">")
    elseif elem isa MarkdownAST.HTMLInline
        print(io, elem.html)
    elseif elem isa MarkdownAST.LineBreak
        print(io, "<br>")
    else
        # Fallback for unknown inline types
        for child in node.children
            _domify_inline(io, child, doc, root_prefix)
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────────────────────────────────────

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
