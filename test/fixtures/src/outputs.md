```@meta
EditURL = "https://example.org/outputs-source.md"
```

# Outputs

Example blocks whose results only offer one rich representation, the way real
packages' plotting and symbolic types do.

```@example outputs
struct OnlyMime{M}
    payload::Vector{UInt8}
end
OnlyMime{M}(s::AbstractString) where {M} = OnlyMime{M}(Vector{UInt8}(s))
Base.show(io::IO, ::MIME"text/plain", ::OnlyMime) = print(io, "OnlyMime")
for m in ("image/jpeg", "image/gif", "image/webp", "image/svg+xml",
          "text/latex", "text/markdown")
    @eval Base.show(io::IO, ::MIME{Symbol($m)}, x::OnlyMime{Symbol($m)}) = write(io, x.payload)
end
nothing
```

```@example outputs
OnlyMime{Symbol("image/jpeg")}(UInt8[0xff, 0xd8, 0xff, 0xe0])
```

```@example outputs
OnlyMime{Symbol("image/gif")}("GIF89a")
```

```@example outputs
OnlyMime{Symbol("image/webp")}("RIFFWEBP")
```

```@example outputs
OnlyMime{Symbol("image/svg+xml")}("<svg width=\"4\" height=\"4\"><rect id=\"clip1\" width=\"4\" height=\"4\"/></svg>")
```

```@example outputs
OnlyMime{Symbol("text/latex")}("\$\$\\alpha^2 + \\beta^2\$\$")
```

```@example outputs
OnlyMime{Symbol("text/markdown")}("Rendered **markdown** output")
```

```@example outputs
struct HtmlWithPng end
Base.show(io::IO, ::MIME"text/html", ::HtmlWithPng) = print(io, "<table class=\"big-html-png\">", "<tr><td>cell</td></tr>"^20, "</table>")
Base.show(io::IO, ::MIME"image/png", ::HtmlWithPng) = write(io, UInt8[0x89, 0x50, 0x4e, 0x47])
HtmlWithPng()
```

```@example outputs
struct HtmlOnly end
Base.show(io::IO, ::MIME"text/html", ::HtmlOnly) = print(io, "<table class=\"big-html-only\">", "<tr><td>cell</td></tr>"^20, "</table>")
HtmlOnly()
```

## Anchors and code

[This sentence is a link target](@id inline-anchor).

```julia filter = r"[0-9]+"
x = 1
```
