#=
Navigation — builds sidebar navigation context from Documenter's navtree.
=#

import Documenter

"""
    NavItem

A single navigation entry (page link or section header).
"""
struct NavItem
    title::String
    path::Union{String,Nothing}   # nothing for section headers
    children::Vector{NavItem}
    visible::Bool
end

"""
    NavContext

Precomputed navigation structure for sidebar rendering.
"""
struct NavContext
    items::Vector{NavItem}
end

"""
    build_nav_context(doc::Documenter.Document) → NavContext

Walk `doc.internal.navtree` and build a renderable navigation tree.
"""
function build_nav_context(doc::Documenter.Document)::NavContext
    items = NavItem[]
    for navnode in doc.internal.navtree
        item = _navnode_to_item(navnode, doc)
        push!(items, item)
    end
    NavContext(items)
end

"""Convert a Documenter.NavNode to a NavItem recursively."""
function _navnode_to_item(node::Documenter.NavNode,
                          doc::Documenter.Document)::NavItem
    # Determine the title
    title_override = node.title_override
    page = node.page
    title = if title_override !== nothing
        title_override::String
    elseif page !== nothing
        _page_title(doc, page::String)
    else
        "Untitled"
    end

    # Build children
    children = NavItem[_navnode_to_item(child, doc) for child in node.children]

    NavItem(title, node.page, children, node.visible)
end

"""Extract the title from a page (first H1, or filename)."""
function _page_title(doc::Documenter.Document, pagepath::String)::String
    if haskey(doc.blueprint.pages, pagepath)
        page = doc.blueprint.pages[pagepath]
        mdast = page.mdast
        for child in mdast.children
            # Handle both bare Heading and Documenter's AnchoredHeader wrapper
            if child.element isa MarkdownAST.Heading && child.element.level == 1
                return _collect_text(child)
            elseif child.element isa Documenter.AnchoredHeader
                for inner in child.children
                    if inner.element isa MarkdownAST.Heading && inner.element.level == 1
                        return _collect_text(inner)
                    end
                end
            end
        end
    end
    # Fallback: use filename without extension
    name = splitext(basename(pagepath))[1]
    replace(titlecase(name), '-' => ' ', '_' => ' ')
end

"""Collect plain text from a MarkdownAST node and its children."""
function _collect_text(node)::String
    io = IOBuffer()
    for child in node.children
        if child.element isa MarkdownAST.Text
            print(io, child.element.text)
        elseif child.element isa MarkdownAST.Code
            print(io, child.element.code)
        else
            # Recurse into inline nodes
            print(io, _collect_text(child))
        end
    end
    String(take!(io))
end
