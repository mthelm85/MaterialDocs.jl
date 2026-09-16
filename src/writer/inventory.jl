#=
Inventory — writes `objects.inv`, the Sphinx-format index of pages, labels and
docstrings that DocumenterInterLinks (and Intersphinx) use to link into a site.

Mirrors Documenter.HTML's `write_inventory` entry for entry, so a package that
switches writers keeps every inbound cross-project link working.
=#

import CodecZlib
import TOML

"""
    write_inventory(doc, settings)

Write `objects.inv` to the build directory.
"""
function write_inventory(doc::Documenter.Document, settings::Material3)
    version = settings.html.inventory_version
    if version === nothing
        version = _inventory_version(joinpath(dirname(doc.user.root), "Project.toml"))
    end

    path = joinpath(doc.user.root, doc.user.build, "objects.inv")
    open(path, "w") do header
        write(header, "# Sphinx inventory version 2\n")
        write(header, "# Project: $(doc.user.sitename)\n")
        write(header, "# Version: $version\n")
        write(header, "# The remainder of this file is compressed using zlib.\n")
        body = CodecZlib.ZlibCompressorStream(header)

        for navnode in doc.internal.navlist
            src = navnode.page
            src === nothing && continue  # section headings have no page
            name = replace(splitext(src)[1], "\\" => "/")
            uri = _escape_uri_path(_pretty_url(settings, _page_url(settings, src)))
            write(body, "$name std:doc -1 $uri $(_inventory_page_title(doc, navnode))\n")
        end

        for name in keys(doc.internal.anchors.map)
            isempty(name) && continue
            anchor = Documenter.anchor(doc.internal.anchors, name)
            anchor === nothing && continue  # not unique
            dispname = Documenter.MDFlatten.mdflatten(anchor.node)
            (isempty(dispname) || dispname == name) && (dispname = "-")
            write(body, "$name std:label -1 $(_inventory_anchor_uri(doc, settings, name, anchor)) $dispname\n")
        end

        for name in keys(doc.internal.docs.map)
            anchor = Documenter.anchor(doc.internal.docs, name)
            anchor === nothing && continue  # not unique
            role = lowercase(Documenter.doccat(anchor.object))
            write(body, "$name jl:$role 1 $(_inventory_anchor_uri(doc, settings, name, anchor)) -\n")
        end

        close(body)
    end
    return path
end

function _inventory_version(project_toml::AbstractString)
    version = ""
    if isfile(project_toml)
        version = string(get(TOML.parsefile(project_toml), "version", ""))
    end
    isempty(version) &&
        @warn "MaterialDocs: could not read a version for objects.inv from $project_toml; set `inventory_version` in Material3()."
    return version
end

"""The output path of a source page, as Documenter.HTML names it."""
function _page_url(settings::Material3, path::AbstractString)
    settings.html.prettyurls || return string(splitext(path)[1], ".html")
    d = basename(path) == "index.md" ? dirname(path) : first(splitext(path))
    return isempty(d) ? "index.html" : "$d/index.html"
end

"""The link form of an output path: `dir/index.html` becomes `dir/` with pretty URLs."""
function _pretty_url(settings::Material3, path::AbstractString)
    if settings.html.prettyurls
        dir, file = splitdir(path)
        file == "index.html" && return isempty(dir) ? "" : "$dir/"
    end
    return path
end

function _inventory_anchor_uri(doc, settings, name, anchor)
    page = _pretty_url(settings, _page_url(settings, relpath(anchor.file, doc.user.build)))
    label = _escape_uri(Documenter.anchor_label(anchor))
    # `$` is the inventory shorthand for "the fragment is the name itself"
    return _escape_uri_path(page) * (label == name ? "#\$" : "#$label")
end

function _inventory_page_title(doc, navnode)
    navnode.title_override === nothing || return navnode.title_override
    page = doc.blueprint.pages[something(navnode.page)]
    for node in page.mdast.children
        node.element isa Documenter.AnchoredHeader && (node = first(node.children))
        if node.element isa MarkdownAST.Heading && node.element.level == 1
            return Documenter.MDFlatten.mdflatten(collect(node.children))
        end
    end
    return "-"
end

_escape_uri_path(path) = join(map(_escape_uri, split(replace(path, "\\" => "/"), "/")), "/")

_uri_safe(c::Char) = c in ('-', '.', '_') || (isascii(c) && (isletter(c) || isnumeric(c)))
_escape_uri(str::AbstractString) = join(
    (_uri_safe(Char(b)) ? Char(b) : string('%', uppercase(string(b, base = 16, pad = 2))))
    for b in codeunits(str))
