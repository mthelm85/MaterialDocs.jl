```@meta
CurrentModule = MaterialDocs
```

# Theming

A MaterialDocs theme is a [`ThemeConfig`](@ref): a seed color, three font
choices, a corner-radius preset, and optional per-role overrides. Everything
else — all 34 MD3 color roles, in both light and dark — is derived from the seed.

## Built-in themes

Pass any of these by name:

```julia
format = Material3(theme = :ocean_depth)
```

| Theme | Seed | Display / Body | Code |
|---|---|---|---|
| `:default` | `#9558B2` | Inter | JetBrains Mono |
| `:ocean_depth` | `#006B5E` | Fira Sans / Source Sans 3 | Fira Code |
| `:solar_flare` | `#B23C17` | Space Grotesk / DM Sans | JetBrains Mono |
| `:midnight` | `#1A237E` | Plus Jakarta Sans | JetBrains Mono |
| `:forest` | `#2E7D32` | Literata / Source Serif 4 | Roboto Mono |
| `:arctic` | `#0277BD` | Inter Tight / Inter | JetBrains Mono |
| `:rose_garden` | `#AD1457` | Playfair Display / Lora | Roboto Mono |
| `:amber_workshop` | `#E65100` | JetBrains Mono / IBM Plex Sans | JetBrains Mono |
| `:lavender` | `#7B1FA2` | DM Serif Display / DM Sans | JetBrains Mono |
| `:sandstone` | `#8D6E63` | Bitter / Libre Baskerville | Roboto Mono |
| `:neon_lab` | `#00BFA5` | Outfit | Fira Code |
| `:slate` | `#455A64` | Atkinson Hyperlegible | Roboto Mono |

They are available programmatically as [`BUILTIN_THEMES`](@ref), and
[`resolve_theme`](@ref) turns a name into a config.

## Custom themes

Build one from a seed color:

```julia
format = Material3(theme = ThemeConfig(
    seed = "#2E7D32",
    display_font = "Literata",
    body_font = "Source Serif 4",
    code_font = "JetBrains Mono",
    corner_radius = :rounded,
))
```

Fonts are [Google Fonts](https://fonts.google.com) family names, requested
automatically at build time.

### Corner radius

`corner_radius` selects a shape scale. Values are the extra-small through full
radii in pixels:

| Preset | Radii (px) |
|---|---|
| `:sharp` | 0, 2, 4, 8, 12, 16 |
| `:default` | 4, 8, 12, 16, 28, full |
| `:rounded` | 8, 12, 20, 28, 36, full |
| `:pill` | 12, 16, 28, 36, 44, full |

### Secondary and tertiary seeds

By default the secondary and tertiary palettes are derived from the primary seed
— secondary at reduced chroma, tertiary rotated 60° around the hue circle. To
control them directly:

```julia
ThemeConfig(
    seed = "#1565C0",
    secondary_seed = "#00897B",
    tertiary_seed = "#E65100",
)
```

### Overriding individual roles

When you need one specific color to be exact, override the role by name. These
are applied after generation, so they win over the derived value:

```julia
ThemeConfig(
    seed = "#1565C0",
    custom_colors = Dict(
        "surface" => "#FAFAFA",
        "primary" => "#0D47A1",
    ),
)
```

!!! warning "Overrides bypass contrast guarantees"
    Generated roles are placed at tones chosen to meet WCAG AA against their
    pairings. An override is used verbatim, so check it yourself with
    [`MaterialColors.meets_aa`](https://mthelm85.github.io/MaterialColors.jl/dev/).

## Configuration files

A theme can live in `docs/.materialdocs.toml` instead of your `make.jl`:

```toml
[theme]
name = "my-theme"
seed = "#1565C0"
secondary_seed = "#00897B"

[theme.fonts]
display = "Fira Sans"
body = "Source Sans 3"
code = "JetBrains Mono"

[theme.shape]
corner_radius = "default"    # sharp | default | rounded | pill

[theme.custom_colors]
surface = "#FAFAFA"
```

**This file is picked up automatically.** When you call `Material3()` without a
`theme` argument, MaterialDocs looks for `docs/.materialdocs.toml` and loads it
if present. Passing `theme` explicitly takes precedence.

This is the format the [Theme Editor](@ref) exports, so the usual workflow is to
design a theme visually, save the file, and never touch `make.jl` at all.

Read and write these files directly with [`load_theme`](@ref) and
[`save_theme`](@ref); [`find_theme_toml`](@ref) performs the search.
