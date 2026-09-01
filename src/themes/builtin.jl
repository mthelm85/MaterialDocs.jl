#=
Built-in Themes

Twelve preset theme configurations covering a range of visual identities.
Each is a named ThemeConfig constant, selectable via Material3(theme = :name).
=#

"""
    BUILTIN_THEMES :: Dict{Symbol,ThemeConfig}

The twelve preset themes, keyed by name. Pass a key to [`Material3`](@ref) or
[`resolve_theme`](@ref) rather than indexing this directly:

```julia
format = Material3(theme = :ocean_depth)
```

Available keys: `:default`, `:ocean_depth`, `:solar_flare`, `:midnight`,
`:forest`, `:arctic`, `:rose_garden`, `:amber_workshop`, `:lavender`,
`:sandstone`, `:neon_lab`, `:slate`.
"""
const BUILTIN_THEMES = Dict{Symbol,ThemeConfig}(
    :default => ThemeConfig(
        name = "Default",
        seed = "#9558B2",
        display_font = "Inter",
        body_font = "Inter",
        code_font = "JetBrains Mono",
        corner_radius = :rounded,
    ),
    :ocean_depth => ThemeConfig(
        name = "Ocean Depth",
        seed = "#006B5E",
        display_font = "Fira Sans",
        body_font = "Source Sans 3",
        code_font = "Fira Code",
        corner_radius = :rounded,
    ),
    :solar_flare => ThemeConfig(
        name = "Solar Flare",
        seed = "#B23C17",
        display_font = "Space Grotesk",
        body_font = "DM Sans",
        code_font = "JetBrains Mono",
        corner_radius = :default,
    ),
    :midnight => ThemeConfig(
        name = "Midnight",
        seed = "#1A237E",
        display_font = "Plus Jakarta Sans",
        body_font = "Plus Jakarta Sans",
        code_font = "JetBrains Mono",
        corner_radius = :rounded,
    ),
    :forest => ThemeConfig(
        name = "Forest",
        seed = "#2E7D32",
        display_font = "Literata",
        body_font = "Source Serif 4",
        code_font = "Roboto Mono",
        corner_radius = :default,
    ),
    :arctic => ThemeConfig(
        name = "Arctic",
        seed = "#0277BD",
        display_font = "Inter Tight",
        body_font = "Inter",
        code_font = "JetBrains Mono",
        corner_radius = :sharp,
    ),
    :rose_garden => ThemeConfig(
        name = "Rose Garden",
        seed = "#AD1457",
        display_font = "Playfair Display",
        body_font = "Lora",
        code_font = "Roboto Mono",
        corner_radius = :rounded,
    ),
    :amber_workshop => ThemeConfig(
        name = "Amber Workshop",
        seed = "#E65100",
        display_font = "JetBrains Mono",
        body_font = "IBM Plex Sans",
        code_font = "JetBrains Mono",
        corner_radius = :default,
    ),
    :lavender => ThemeConfig(
        name = "Lavender",
        seed = "#7B1FA2",
        display_font = "DM Serif Display",
        body_font = "DM Sans",
        code_font = "JetBrains Mono",
        corner_radius = :rounded,
    ),
    :sandstone => ThemeConfig(
        name = "Sandstone",
        seed = "#8D6E63",
        display_font = "Bitter",
        body_font = "Libre Baskerville",
        code_font = "Roboto Mono",
        corner_radius = :default,
    ),
    :neon_lab => ThemeConfig(
        name = "Neon Lab",
        seed = "#00BFA5",
        display_font = "Outfit",
        body_font = "Outfit",
        code_font = "Fira Code",
        corner_radius = :pill,
    ),
    :slate => ThemeConfig(
        name = "Slate",
        seed = "#455A64",
        display_font = "Atkinson Hyperlegible",
        body_font = "Atkinson Hyperlegible",
        code_font = "Roboto Mono",
        corner_radius = :rounded,
    ),
)

"""
    resolve_theme(theme) → ThemeConfig

Resolve a theme argument to a ThemeConfig. Accepts:
- A `ThemeConfig` (returned as-is)
- A `Symbol` naming a built-in theme (e.g. `:default`, `:ocean_depth`)

Throws `ArgumentError` if the symbol is not a known built-in theme.
"""
function resolve_theme(theme::ThemeConfig)::ThemeConfig
    theme
end

function resolve_theme(theme::Symbol)::ThemeConfig
    haskey(BUILTIN_THEMES, theme) ||
        throw(ArgumentError(
            "Unknown built-in theme :$theme. Available themes: " *
            join(sort(collect(keys(BUILTIN_THEMES))), ", ", ", and ")))
    BUILTIN_THEMES[theme]
end
