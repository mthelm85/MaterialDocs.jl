#=
Domify — AST node → HTML dispatch.

Each Documenter/MarkdownAST node type has a dedicated `domify` method that
renders it to semantic HTML with MD3 class names. A `DomifyContext` carries
the shared state needed across the tree walk.
=#

import Documenter
import MarkdownAST

# ─────────────────────────────────────────────────────────────────────────────
# Context
# ─────────────────────────────────────────────────────────────────────────────

"""
    DomifyContext

Shared state threaded through the AST → HTML tree walk.
"""
struct DomifyContext
    io::IOBuffer
    doc::Documenter.Document
    page::Documenter.Page
    root_prefix::String
    settings::Material3
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

"""
    domify(ctx, node)

Render a MarkdownAST `node` and all its descendants to HTML,
writing into `ctx.io`. Dispatches on `node.element`.
"""
function domify(ctx::DomifyContext, node)
    domify(ctx, node, node.element)
end

"""Fallback — render children when no specific method exists."""
function domify(ctx::DomifyContext, node, ::MarkdownAST.AbstractElement)
    domify_children(ctx, node)
end

"""Render all children of a node."""
function domify_children(ctx::DomifyContext, node)
    for child in node.children
        domify(ctx, child)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# MarkdownAST block elements
# ─────────────────────────────────────────────────────────────────────────────

function domify(ctx::DomifyContext, node, ::MarkdownAST.Document)
    domify_children(ctx, node)
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Heading)
    text = _collect_text(node)
    slug = _slugify(text)
    level = elem.level
    io = ctx.io
    print(io, "<h", level, " id=\"", slug, "\" class=\"md-heading\">")
    domify_children(ctx, node)
    # Anchor link for heading
    print(io, "<a href=\"#", slug, "\" class=\"md-heading-anchor\" aria-label=\"Link to this section\">#</a>")
    println(io, "</h", level, ">")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Paragraph)
    io = ctx.io
    print(io, "<p>")
    domify_children(ctx, node)
    println(io, "</p>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.CodeBlock)
    io = ctx.io
    lang = elem.info
    lang_attr = isempty(lang) ? "" : " class=\"language-$lang\""
    println(io, "<div class=\"md-code-block\">")
    println(io, "<button class=\"md-copy-btn\" title=\"Copy to clipboard\" aria-label=\"Copy code\">",
            "<span class=\"md-copy-icon\">⧉</span><span class=\"md-copy-feedback\">Copied!</span></button>")
    print(io, "<pre><code", lang_attr, ">")
    print(io, _html_escape(elem.code))
    println(io, "</code></pre>")
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.List)
    io = ctx.io
    tag = elem.type === :ordered ? "ol" : "ul"
    tight_class = elem.tight ? " class=\"md-list-tight\"" : ""
    println(io, "<", tag, tight_class, ">")
    domify_children(ctx, node)
    println(io, "</", tag, ">")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Item)
    io = ctx.io
    print(io, "<li>")
    domify_children(ctx, node)
    println(io, "</li>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.BlockQuote)
    io = ctx.io
    println(io, "<blockquote class=\"md-blockquote\">")
    domify_children(ctx, node)
    println(io, "</blockquote>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.ThematicBreak)
    println(ctx.io, "<hr class=\"md-hr\">")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.HTMLBlock)
    println(ctx.io, elem.html)
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Admonition)
    io = ctx.io
    cat = elem.category
    println(io, "<div class=\"md-admonition md-admonition-", _html_escape(cat), "\">")
    println(io, "<p class=\"md-admonition-title\">", _html_escape(elem.title), "</p>")
    println(io, "<div class=\"md-admonition-body\">")
    domify_children(ctx, node)
    println(io, "</div>")
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.FootnoteDefinition)
    io = ctx.io
    println(io, "<div class=\"md-footnote\" id=\"fn-", _html_escape(elem.id), "\">")
    print(io, "<span class=\"md-footnote-label\">", _html_escape(elem.id), "</span>")
    domify_children(ctx, node)
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.DisplayMath)
    io = ctx.io
    println(io, "<div class=\"md-math md-math-display\">")
    println(io, "\\[", _html_escape(elem.math), "\\]")
    println(io, "</div>")
end

# ── Tables ──

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Table)
    io = ctx.io
    println(io, "<div class=\"md-table-wrap\">")
    println(io, "<table class=\"md-table\">")
    domify_children(ctx, node)
    println(io, "</table>")
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.TableHeader)
    io = ctx.io
    println(io, "<thead>")
    domify_children(ctx, node)
    println(io, "</thead>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.TableBody)
    io = ctx.io
    println(io, "<tbody>")
    domify_children(ctx, node)
    println(io, "</tbody>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.TableRow)
    io = ctx.io
    println(io, "<tr>")
    domify_children(ctx, node)
    println(io, "</tr>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.TableCell)
    io = ctx.io
    tag = elem.header ? "th" : "td"
    align_attr = if elem.align === :left
        " style=\"text-align:left\""
    elseif elem.align === :right
        " style=\"text-align:right\""
    elseif elem.align === :center
        " style=\"text-align:center\""
    else
        ""
    end
    print(io, "<", tag, align_attr, ">")
    domify_children(ctx, node)
    println(io, "</", tag, ">")
end

# ─────────────────────────────────────────────────────────────────────────────
# MarkdownAST inline elements
# ─────────────────────────────────────────────────────────────────────────────

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Text)
    print(ctx.io, _html_escape(elem.text))
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Code)
    print(ctx.io, "<code class=\"md-code-inline\">", _html_escape(elem.code), "</code>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Emph)
    io = ctx.io
    print(io, "<em>")
    domify_children(ctx, node)
    print(io, "</em>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Strong)
    io = ctx.io
    print(io, "<strong>")
    domify_children(ctx, node)
    print(io, "</strong>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Link)
    io = ctx.io
    print(io, "<a href=\"", _html_escape(elem.destination), "\">")
    domify_children(ctx, node)
    print(io, "</a>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.Image)
    io = ctx.io
    alt = _collect_text(node)
    println(io, "<figure class=\"md-figure\">")
    print(io, "<img src=\"", _html_escape(elem.destination), "\" alt=\"", _html_escape(alt), "\"")
    println(io, " loading=\"lazy\">")
    if !isempty(alt)
        println(io, "<figcaption>", _html_escape(alt), "</figcaption>")
    end
    println(io, "</figure>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.HTMLInline)
    print(ctx.io, elem.html)
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.LineBreak)
    print(ctx.io, "<br>")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.SoftBreak)
    print(ctx.io, "\n")
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Backslash)
    # Backslash is just an escape — render children
    domify_children(ctx, node)
end

function domify(ctx::DomifyContext, node, ::MarkdownAST.Strikethrough)
    io = ctx.io
    print(io, "<del>")
    domify_children(ctx, node)
    print(io, "</del>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.FootnoteLink)
    io = ctx.io
    print(io, "<sup class=\"md-footnote-ref\"><a href=\"#fn-",
          _html_escape(elem.id), "\">[", _html_escape(elem.id), "]</a></sup>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.InlineMath)
    print(ctx.io, "<span class=\"md-math md-math-inline\">\\(", _html_escape(elem.math), "\\)</span>")
end

function domify(ctx::DomifyContext, node, elem::MarkdownAST.JuliaValue)
    io = ctx.io
    # Render the Julia value using show — this handles @example output
    if elem.ref isa MarkdownAST.Node
        # If it wraps another node, render that
        domify(ctx, elem.ref)
    else
        # Fall back to showing the expression
        val = elem.ex
        if val !== nothing
            print(io, "<pre class=\"md-julia-value\"><code>")
            print(io, _html_escape(sprint(show, "text/plain", val)))
            print(io, "</code></pre>")
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Documenter-specific block elements
# ─────────────────────────────────────────────────────────────────────────────

function domify(ctx::DomifyContext, node, elem::Documenter.AnchoredHeader)
    io = ctx.io
    anchor = elem.anchor
    # The AnchoredHeader wraps a Heading node — render it with the anchor id
    for child in node.children
        if child.element isa MarkdownAST.Heading
            level = child.element.level
            slug = Documenter.anchor_label(anchor)
            print(io, "<h", level, " id=\"", _html_escape(slug), "\" class=\"md-heading\">")
            domify_children(ctx, child)
            print(io, "<a href=\"#", _html_escape(slug),
                  "\" class=\"md-heading-anchor\" aria-label=\"Link to this section\">#</a>")
            println(io, "</h", level, ">")
        else
            domify(ctx, child)
        end
    end
end

function domify(ctx::DomifyContext, node, elem::Documenter.DocsNode)
    io = ctx.io
    anchor = elem.anchor
    slug = Documenter.anchor_label(anchor)
    binding = elem.object.binding
    sig = elem.object.signature

    println(io, "<div class=\"md-docstring\" id=\"", _html_escape(slug), "\">")

    # Binding header with optional source link
    println(io, "<div class=\"md-docstring-header\">")
    print(io, "<h4 class=\"md-docstring-binding\"><code>")
    print(io, _html_escape(string(binding)))
    print(io, "</code>")
    # Signature if present
    if sig !== Union{}
        print(io, " — <span class=\"md-docstring-sig\">")
        print(io, _html_escape(string(sig)))
        print(io, "</span>")
    end
    println(io, "</h4>")

    # Source link — try each docstring result
    # Wrapped in try-catch because Documenter.source_url can fail when
    # unregistered packages are in the manifest (Pkg can't resolve their paths)
    for docstr in elem.results
        try
            url = Documenter.source_url(ctx.doc, docstr)
            if url !== nothing
                println(io, "<a class=\"md-docstring-source\" href=\"", _html_escape(url),
                        "\" title=\"View source\">source</a>")
                break  # one link is enough
            end
        catch
            # Skip source link if we can't resolve the URL
        end
    end

    println(io, "</div>")  # md-docstring-header

    # Render each docstring markdown AST
    for mdast in elem.mdasts
        println(io, "<div class=\"md-docstring-content\">")
        domify_children(ctx, mdast)
        println(io, "</div>")
    end

    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, ::Documenter.DocsNodesBlock)
    # Container for DocsNode nodes — just render children
    domify_children(ctx, node)
end

function domify(ctx::DomifyContext, node, elem::Documenter.MultiOutput)
    io = ctx.io
    println(io, "<div class=\"md-multi-output\">")
    domify_children(ctx, node)
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, elem::Documenter.MultiOutputElement)
    io = ctx.io
    result = elem.element
    if result isa Dict
        # MIME-dispatched output from @example blocks
        # Prefer text/html, then image/svg+xml, then image/png, then text/plain
        if haskey(result, MIME"text/html"())
            println(io, "<div class=\"md-output md-output-html\">")
            println(io, result[MIME"text/html"()])
            println(io, "</div>")
        elseif haskey(result, MIME"image/svg+xml"())
            println(io, "<div class=\"md-output md-output-svg\">")
            println(io, result[MIME"image/svg+xml"()])
            println(io, "</div>")
        elseif haskey(result, MIME"image/png"())
            println(io, "<div class=\"md-output md-output-img\">")
            imgdata = result[MIME"image/png"()]
            println(io, "<img src=\"data:image/png;base64,", imgdata, "\">")
            println(io, "</div>")
        elseif haskey(result, MIME"text/plain"())
            println(io, "<pre class=\"md-output md-output-text\"><code>")
            print(io, _html_escape(result[MIME"text/plain"()]))
            println(io, "</code></pre>")
        end
    else
        # Fallback: render children if it's a node tree
        domify_children(ctx, node)
    end
end

function domify(ctx::DomifyContext, node, elem::Documenter.MultiCodeBlock)
    io = ctx.io
    lang = elem.language
    println(io, "<div class=\"md-code-block\">")
    println(io, "<button class=\"md-copy-btn\" title=\"Copy to clipboard\" aria-label=\"Copy code\">",
            "<span class=\"md-copy-icon\">⧉</span><span class=\"md-copy-feedback\">Copied!</span></button>")
    print(io, "<pre><code class=\"language-", _html_escape(lang), "\">")
    for code_block in elem.content
        print(io, _html_escape(code_block.code))
    end
    println(io, "</code></pre>")
    println(io, "</div>")
end

function domify(ctx::DomifyContext, node, elem::Documenter.RawNode)
    # Only pass through :html raw nodes
    if elem.name === :html
        println(ctx.io, elem.text)
    end
    # Other formats (e.g. :latex) are silently ignored
end

function domify(ctx::DomifyContext, node, elem::Documenter.ContentsNode)
    io = ctx.io
    # Documenter fills `elements` with (order, page, anchor) tuples — not Pairs.
    println(io, "<nav class=\"md-contents\">")
    println(io, "<ul>")
    for (_, page, anchor) in elem.elements
        href = _xref_href(ctx, page, Documenter.anchor_label(anchor))
        title = _collect_text(anchor.node)
        println(io, "<li><a href=\"", _html_escape(href), "\">", _html_escape(title), "</a></li>")
    end
    println(io, "</ul>")
    println(io, "</nav>")
end

function domify(ctx::DomifyContext, node, elem::Documenter.IndexNode)
    io = ctx.io
    # Documenter fills `elements` with (object, doc, page, mod, cat) tuples —
    # not Pairs. The anchor matches the id DocsNode writes for the docstring.
    println(io, "<div class=\"md-index\">")
    println(io, "<ul>")
    for (object, _, page, _, _) in elem.elements
        href = _xref_href(ctx, page, Documenter.slugify(object))
        println(io, "<li><a href=\"", _html_escape(href), "\"><code>",
                _html_escape(Documenter.bindingstring(object.binding)), "</code></a></li>")
    end
    println(io, "</ul>")
    println(io, "</div>")
end

"""
Build a link from the current page to `fragment` on `page`, honouring
`prettyurls`. A page equal to the current one yields a bare fragment so the
link stays valid regardless of how the page is served.
"""
function _xref_href(ctx::DomifyContext, page::AbstractString, fragment::AbstractString)
    src = replace(ctx.page.source, '\\' => '/')
    tgt = replace(String(page), '\\' => '/')
    endswith(src, tgt) && return string("#", fragment)
    string(ctx.root_prefix, _nav_href(tgt, ctx.settings.prettyurls), "#", fragment)
end

function domify(ctx::DomifyContext, node, ::Documenter.EvalNode)
    # @eval blocks — render children (the result, if any)
    domify_children(ctx, node)
end

function domify(ctx::DomifyContext, node, ::Documenter.MetaNode)
    # @meta blocks are invisible — produce no output
end

function domify(ctx::DomifyContext, node, ::Documenter.SetupNode)
    # @setup blocks are invisible — produce no output
end

# ─────────────────────────────────────────────────────────────────────────────
# Documenter-specific inline elements
# ─────────────────────────────────────────────────────────────────────────────

function domify(ctx::DomifyContext, node, elem::Documenter.PageLink)
    io = ctx.io
    page = elem.page
    # page.build is like "build/api.md" — extract relative part and convert
    # Normalize separators to "/" for consistent matching across platforms
    _norm(p) = replace(p, '\\' => '/')
    build_prefix = _norm(ctx.doc.user.build) * "/"
    page_path = _norm(page.build)
    if startswith(page_path, build_prefix)
        page_path = page_path[length(build_prefix)+1:end]
    end
    href = ctx.root_prefix * _nav_href(page_path, ctx.settings.prettyurls)
    if !isempty(elem.fragment)
        href *= "#" * elem.fragment
    end
    print(io, "<a href=\"", _html_escape(href), "\">")
    domify_children(ctx, node)
    print(io, "</a>")
end

function domify(ctx::DomifyContext, node, elem::Documenter.LocalLink)
    io = ctx.io
    href = elem.path
    if !isempty(elem.fragment)
        href *= "#" * elem.fragment
    end
    print(io, "<a href=\"", _html_escape(href), "\">")
    domify_children(ctx, node)
    print(io, "</a>")
end

function domify(ctx::DomifyContext, node, elem::Documenter.LocalImage)
    io = ctx.io
    alt = _collect_text(node)
    println(io, "<figure class=\"md-figure\">")
    print(io, "<img src=\"", _html_escape(elem.path), "\" alt=\"", _html_escape(alt), "\"")
    println(io, " loading=\"lazy\">")
    if !isempty(alt)
        println(io, "<figcaption>", _html_escape(alt), "</figcaption>")
    end
    println(io, "</figure>")
end
