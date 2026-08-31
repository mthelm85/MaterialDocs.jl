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

"""
    Material3 <: Documenter.Writer

A Documenter.jl writer that generates Material Design 3 documentation sites.

# Keywords
- `theme = :default`: Built-in theme name (`Symbol`) or a [`ThemeConfig`](@ref).
  When `:default`, automatically loads `docs/.materialdocs.toml` if present.
- `dark_mode = :auto`: Dark mode behavior. One of:
  - `:auto` — follows `prefers-color-scheme`
  - `:light` — always light
  - `:dark` — always dark
  - `:toggle` — adds a light/dark toggle button
- `sidebar_collapsed = false`: Start sidebar sections collapsed.
- `toc_depth = 3`: Right-rail table-of-contents heading depth (2–4).
- `search = true`: Enable the search bar.
- `repolink = :auto`: Link to the source repository in the navbar. One of:
  - `:auto` — derive from Documenter's configured remote (`makedocs(repo = ...)`)
  - a `String` — an explicit URL
  - `nothing` — omit the link
- `versions = true`: Show a version selector when `deploydocs` has generated
  `versions.js` / `siteinfo.js`. Hidden automatically on non-deployed builds.
- `analytics = nothing`: Google Analytics measurement ID (e.g. `"G-XXXXXXXXXX"`).
- `logo = nothing`: Path to logo image (relative to docs/src).
- `favicon = nothing`: Path to favicon (relative to docs/src).
- `footer = nothing`: Custom footer HTML string.
- `custom_css = String[]`: Additional CSS files to include.
- `custom_js = String[]`: Additional JS files to include.
- `prettyurls = true`: Use clean URLs (`page/index.html` instead of `page.html`).

# Examples
```julia
# Use a built-in theme
format = Material3(theme = :ocean_depth)

# Use a custom theme
format = Material3(theme = ThemeConfig(seed = "#E65100", display_font = "Space Grotesk"))

# Full configuration
format = Material3(
    theme = :midnight,
    dark_mode = :toggle,
    toc_depth = 4,
    logo = "assets/logo.svg",
    footer = "Made with ❤️ and Julia",
)
```
"""
struct Material3 <: Documenter.Writer
    theme::ThemeConfig
    dark_mode::Symbol
    sidebar_collapsed::Bool
    toc_depth::Int
    search::Bool
    repolink::Union{String,Nothing,Symbol}
    versions::Bool
    analytics::Union{String,Nothing}
    logo::Union{String,Nothing}
    favicon::Union{String,Nothing}
    footer::Union{String,Nothing}
    custom_css::Vector{String}
    custom_js::Vector{String}
    prettyurls::Bool
end

function Material3(;
    theme::Union{Symbol,ThemeConfig} = :default,
    dark_mode::Symbol = :auto,
    sidebar_collapsed::Bool = false,
    toc_depth::Int = 3,
    search::Bool = true,
    repolink::Union{AbstractString,Nothing,Symbol} = :auto,
    versions::Bool = true,
    analytics::Union{AbstractString,Nothing} = nothing,
    logo::Union{AbstractString,Nothing} = nothing,
    favicon::Union{AbstractString,Nothing} = nothing,
    footer::Union{AbstractString,Nothing} = nothing,
    custom_css::Vector{String} = String[],
    custom_js::Vector{String} = String[],
    prettyurls::Bool = true,
)
    dark_mode in (:auto, :light, :dark, :toggle) ||
        throw(ArgumentError("dark_mode must be :auto, :light, :dark, or :toggle"))
    2 <= toc_depth <= 4 ||
        throw(ArgumentError("toc_depth must be between 2 and 4"))
    repolink isa Symbol && repolink !== :auto &&
        throw(ArgumentError("repolink must be :auto, a URL string, or nothing"))

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

    Material3(resolved_theme, dark_mode, sidebar_collapsed, toc_depth,
              search,
              repolink isa AbstractString ? String(repolink) : repolink,
              versions,
              analytics === nothing ? nothing : String(analytics),
              logo === nothing ? nothing : String(logo),
              favicon === nothing ? nothing : String(favicon),
              footer === nothing ? nothing : String(footer),
              custom_css, custom_js, prettyurls)
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
