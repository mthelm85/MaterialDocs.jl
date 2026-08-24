#=
Theme Configuration

Defines the ThemeConfig struct that controls all visual aspects of a
MaterialDocs site: seed colors, fonts, corner radii, and per-role overrides.
=#

"""
    ThemeConfig

Configuration for a MaterialDocs theme. Controls colors (via HCT seed),
typography (via Google Fonts names), shape, and per-role color overrides.

# Fields
- `name::String`: Human-readable theme name.
- `seed::String`: Primary seed hex color (e.g. `"#6750A4"`).
- `secondary_seed::Union{String,Nothing}`: Override secondary palette seed.
- `tertiary_seed::Union{String,Nothing}`: Override tertiary palette seed.
- `display_font::String`: Google Fonts name for headings.
- `body_font::String`: Google Fonts name for body text.
- `code_font::String`: Google Fonts name for code blocks.
- `corner_radius::Symbol`: `:sharp`, `:slight`, `:rounded`, or `:full`.
- `custom_colors::Dict{String,String}`: Override individual MD3 color roles.

# Examples
```julia
theme = ThemeConfig(seed = "#2E7D32", display_font = "Literata")
```
"""
struct ThemeConfig
    name::String
    seed::String
    secondary_seed::Union{String,Nothing}
    tertiary_seed::Union{String,Nothing}
    display_font::String
    body_font::String
    code_font::String
    corner_radius::Symbol
    custom_colors::Dict{String,String}
end

"""
    ThemeConfig(; kwargs...)

Construct a theme configuration with sensible defaults.

# Keywords
- `name = "custom"`: Theme name.
- `seed = "#6750A4"`: Primary seed hex color.
- `secondary_seed = nothing`: Auto-derived if `nothing`.
- `tertiary_seed = nothing`: Auto-derived if `nothing`.
- `display_font = "Roboto"`: Google Fonts heading font.
- `body_font = "Roboto"`: Google Fonts body font.
- `code_font = "Roboto Mono"`: Google Fonts code font.
- `corner_radius = :rounded`: Shape preset.
- `custom_colors = Dict{String,String}()`: Per-role color overrides.
"""
function ThemeConfig(;
    name::AbstractString = "custom",
    seed::AbstractString = "#6750A4",
    secondary_seed::Union{AbstractString,Nothing} = nothing,
    tertiary_seed::Union{AbstractString,Nothing} = nothing,
    display_font::AbstractString = "Roboto",
    body_font::AbstractString = "Roboto",
    code_font::AbstractString = "Roboto Mono",
    corner_radius::Symbol = :rounded,
    custom_colors::Dict{String,String} = Dict{String,String}(),
)
    corner_radius in (:sharp, :slight, :rounded, :full) ||
        throw(ArgumentError("corner_radius must be :sharp, :slight, :rounded, or :full"))
    ThemeConfig(String(name), String(seed),
                secondary_seed === nothing ? nothing : String(secondary_seed),
                tertiary_seed === nothing ? nothing : String(tertiary_seed),
                String(display_font), String(body_font), String(code_font),
                corner_radius, custom_colors)
end

function Base.show(io::IO, t::ThemeConfig)
    print(io, "ThemeConfig(\"", t.name, "\", seed=", t.seed, ")")
end

# ─────────────────────────────────────────────────────────────────────────────
# Corner radius presets → CSS values (in px)
# ─────────────────────────────────────────────────────────────────────────────

"""
Corner radius presets mapping to (extra-small, small, medium, large,
extra-large, full) CSS border-radius values in pixels.
"""
const CORNER_RADII = Dict{Symbol,NTuple{6,Int}}(
    :sharp   => (0,  0,  0,  0,  0,  0),
    :slight  => (2,  4,  6,  8, 12, 16),
    :rounded => (4,  8, 12, 16, 28, 28),
    :full    => (8, 12, 16, 28, 28, 28),
)
