#=
Writer — Material3 struct and Documenter.jl FormatSelector registration.

This is the integration point between MaterialDocs and Documenter.jl.
We register a FormatSelector that dispatches to our render() when
the user passes Material3() as the format in makedocs().

Usage:
    using Documenter, MaterialDocs

    makedocs(;
        sitename = "MyPackage.jl",
        format = Material3(theme = :ocean_depth),
        ...
    )
=#

import Documenter

const DEFAULT_FOOTER = "Built with [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) and [MaterialDocs.jl](https://github.com/mthelm85/MaterialDocs.jl)."

# Documenter.HTML keywords that only affect Documenter's own theme
const IGNORED_HTML_KEYWORDS = (:prerender, :node, :highlightjs)

"""
    Material3 <: Documenter.Writer

A Documenter.jl writer that generates Material Design 3 documentation sites.

`Material3` accepts every keyword [`Documenter.HTML`](https://documenter.juliadocs.org/stable/lib/public/#Documenter.HTML)
does, with the same meaning and defaults, so switching writers is a rename:
`format = Documenter.HTML(...)` becomes `format = Material3(...)`. Those
keywords are validated by constructing a `Documenter.HTML`, available as the
`html` field. `prerender`, `node` and `highlightjs` are accepted but have no
effect.

# MaterialDocs keywords
- `theme = :default`: Built-in theme name (`Symbol`) or a [`ThemeConfig`](@ref).
  When `:default`, automatically loads `docs/.materialdocs.toml` if present.
- `dark_mode = :auto`: Dark mode behavior. One of:
  - `:auto` — follows `prefers-color-scheme`
  - `:light` — always light
  - `:dark` — always dark
  - `:toggle` — adds a light/dark toggle button
- `toc_depth = 3`: Right-rail table-of-contents heading depth (2–4).
- `search = true`: Enable the search bar.
- `versions = true`: Show a version selector when `deploydocs` has generated
  `versions.js` / `siteinfo.js`. Hidden automatically on non-deployed builds.
- `logo = nothing`: Path to a logo image (relative to docs/src). When `nothing`,
  `assets/logo.{svg,png,webp,gif,jpg,jpeg}` is used if present, as in Documenter.
- `favicon = nothing`: Path to a favicon (relative to docs/src). An `.ico` in
  `assets` works too, as in Documenter.

`repolink` additionally accepts `:auto`, the same as leaving it unset.

# Examples
```julia
# Use a built-in theme
format = Material3(theme = :ocean_depth)

# Use a custom theme
format = Material3(theme = ThemeConfig(seed = "#E65100", display_font = "Space Grotesk"))

# Documenter.HTML options carry over unchanged
format = Material3(
    theme = :midnight,
    dark_mode = :toggle,
    canonical = "https://you.github.io/MyPackage.jl/stable",
    assets = ["assets/extra.css"],
    footer = "Made with ❤️ and Julia",
)
```
"""
struct Material3 <: Documenter.Writer
    theme::ThemeConfig
    dark_mode::Symbol
    toc_depth::Int
    search::Bool
    versions::Bool
    logo::Union{String,Nothing}
    favicon::Union{String,Nothing}
    html::Documenter.HTML
end

function Material3(;
    theme::Union{Symbol,ThemeConfig} = :default,
    dark_mode::Symbol = :auto,
    toc_depth::Int = 3,
    search::Bool = true,
    versions::Bool = true,
    logo::Union{AbstractString,Nothing} = nothing,
    favicon::Union{AbstractString,Nothing} = nothing,
    repolink::Union{AbstractString,Nothing,Symbol} = :auto,
    footer::Union{AbstractString,Nothing} = DEFAULT_FOOTER,
    html_kwargs...,
)
    dark_mode in (:auto, :light, :dark, :toggle) ||
        throw(ArgumentError("dark_mode must be :auto, :light, :dark, or :toggle"))
    2 <= toc_depth <= 4 ||
        throw(ArgumentError("toc_depth must be between 2 and 4"))
    repolink isa Symbol && repolink !== :auto &&
        throw(ArgumentError("repolink must be :auto, a URL string, or nothing"))

    for kw in IGNORED_HTML_KEYWORDS
        haskey(html_kwargs, kw) &&
            @warn "MaterialDocs: `$kw` only applies to Documenter's own theme and has no effect with Material3."
    end
    # Not forwarded: `prerender = true` would make Documenter look for Node.js
    forwarded = (k => v for (k, v) in pairs(html_kwargs) if !(k in IGNORED_HTML_KEYWORDS))
    html = repolink === :auto ?
        Documenter.HTML(; footer, forwarded...) :
        Documenter.HTML(; footer, repolink, forwarded...)

    # Auto-detect .materialdocs.toml when no explicit theme is provided
    resolved_theme = if theme === :default
        toml_path = find_theme_toml("docs")
        if toml_path !== nothing
            @info "MaterialDocs: loading theme from $toml_path"
            load_theme(toml_path)
        else
            resolve_theme(:default)
        end
    else
        resolve_theme(theme)
    end

    Material3(resolved_theme, dark_mode, toc_depth, search, versions,
              logo === nothing ? nothing : String(logo),
              favicon === nothing ? nothing : String(favicon),
              html)
end

function Base.show(io::IO, m::Material3)
    print(io, "Material3(\"", m.theme.name, "\"",
          m.dark_mode != :auto ? ", dark_mode=:$(m.dark_mode)" : "",
          ")")
end

# ─────────────────────────────────────────────────────────────────────────────
# FormatSelector registration
# ─────────────────────────────────────────────────────────────────────────────

abstract type MaterialFormat <: Documenter.FormatSelector end

Documenter.Selectors.order(::Type{MaterialFormat}) = 0.0
Documenter.Selectors.matcher(::Type{MaterialFormat}, fmt, _) = isa(fmt, Material3)

function Documenter.Selectors.runner(::Type{MaterialFormat}, fmt, doc)
    render(doc, fmt)
end
