#=
Color Scheme — generates 29+ MD3 color roles from seed color(s).

Based on the dynamic color algorithm from Google's material-color-utilities.
Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0.
https://github.com/material-foundation/material-color-utilities
See LICENSES_THIRD_PARTY.md for the full license text.

Implements the Material Design 3 dynamic color algorithm:
1. Convert seed → HCT
2. Derive five key palettes (Primary, Secondary, Tertiary, Neutral, Neutral-Variant)
3. Map each color role to a specific palette + tone
=#

# ─────────────────────────────────────────────────────────────────────────────
# Palette derivation rules
# ─────────────────────────────────────────────────────────────────────────────

# From the seed HCT, derive five key palettes:
#   Primary:         seed hue, seed chroma (max achievable)
#   Secondary:       seed hue, chroma ≈ 16
#   Tertiary:        seed hue + 60°, chroma ≈ 24
#   Neutral:         seed hue, chroma ≈ 4
#   Neutral-Variant: seed hue, chroma ≈ 8
#   Error:           fixed hue 25°, chroma 84 (red)

const ERROR_HUE = 25.0
const ERROR_CHROMA = 84.0
const SECONDARY_CHROMA = 16.0
const TERTIARY_HUE_OFFSET = 60.0
const TERTIARY_CHROMA = 24.0
const NEUTRAL_CHROMA = 4.0
const NEUTRAL_VARIANT_CHROMA = 8.0

# ─────────────────────────────────────────────────────────────────────────────
# Tone mapping (ColorSpec2021)
# ─────────────────────────────────────────────────────────────────────────────

# Each role maps to (palette_symbol, light_tone, dark_tone)
# Palette symbols: :P (primary), :S (secondary), :T (tertiary),
#                  :E (error), :N (neutral), :NV (neutral-variant)

const ROLE_MAPPING = (
    # Primary group
    primary                   = (:P,   40,  80),
    on_primary                = (:P,  100,  20),
    primary_container         = (:P,   90,  30),
    on_primary_container      = (:P,   10,  90),

    # Secondary group
    secondary                 = (:S,   40,  80),
    on_secondary              = (:S,  100,  20),
    secondary_container       = (:S,   90,  30),
    on_secondary_container    = (:S,   10,  90),

    # Tertiary group
    tertiary                  = (:T,   40,  80),
    on_tertiary               = (:T,  100,  20),
    tertiary_container        = (:T,   90,  30),
    on_tertiary_container     = (:T,   10,  90),

    # Error group
    error                     = (:E,   40,  80),
    on_error                  = (:E,  100,  20),
    error_container           = (:E,   90,  30),
    on_error_container        = (:E,   10,  90),

    # Surface group (Neutral palette)
    surface                   = (:N,   98,   6),
    on_surface                = (:N,   10,  90),
    surface_dim               = (:N,   87,   6),
    surface_bright            = (:N,   98,  24),
    surface_container_lowest  = (:N,  100,   4),
    surface_container_low     = (:N,   96,  10),
    surface_container         = (:N,   94,  12),
    surface_container_high    = (:N,   92,  17),
    surface_container_highest = (:N,   90,  22),

    # Surface variant group (Neutral-Variant palette)
    surface_variant           = (:NV,  90,  30),
    on_surface_variant        = (:NV,  30,  80),
    outline                   = (:NV,  50,  60),
    outline_variant           = (:NV,  80,  30),

    # Inverse group
    inverse_surface           = (:N,   20,  90),
    inverse_on_surface        = (:N,   95,  20),
    inverse_primary           = (:P,   80,  40),

    # Fixed roles
    scrim                     = (:N,    0,   0),
    shadow                    = (:N,    0,   0),
)

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

"""
    color_scheme(seed; dark=false, secondary=nothing, tertiary=nothing,
                 contrast=:standard) → Dict{Symbol,String}

Generate a complete MD3 color scheme (29+ roles) from a seed color.

# Arguments
- `seed::AbstractString`: Primary seed hex color (e.g. `"#6750A4"`).
- `dark::Bool=false`: Generate dark mode scheme if true.
- `secondary::Union{AbstractString,Nothing}=nothing`: Override the derived
  secondary palette with a custom seed hex.
- `tertiary::Union{AbstractString,Nothing}=nothing`: Override the derived
  tertiary palette with a custom seed hex.
- `contrast::Symbol=:standard`: Contrast level (`:standard`, `:medium`, `:high`).
  Currently only `:standard` is implemented.

# Returns
A `Dict{Symbol,String}` mapping role names (e.g. `:primary`, `:on_surface`)
to hex color strings.

# Examples
```julia
scheme = color_scheme("#6750A4")
scheme[:primary]            # "#6750A4" (approximately)
scheme[:primary_container]  # light purple

dark_scheme = color_scheme("#6750A4"; dark=true)
dark_scheme[:primary]       # "#D0BCFF" (lighter for dark backgrounds)
```
"""
function color_scheme(seed::AbstractString;
                      dark::Bool = false,
                      secondary::Union{AbstractString,Nothing} = nothing,
                      tertiary::Union{AbstractString,Nothing} = nothing,
                      contrast::Symbol = :standard)::Dict{Symbol,String}
    contrast === :standard || @warn "Only :standard contrast is currently implemented"

    # Parse seed and extract hue/chroma
    seed_hct = hct(seed)
    seed_hue = seed_hct.hue

    # Build the five key palettes + error
    palettes = Dict{Symbol,TonalPalette}(
        :P  => TonalPalette(seed_hue, seed_hct.chroma),
        :S  => if secondary !== nothing
                   tp = tonal_palette(secondary)
                   TonalPalette(tp.hue, tp.chroma)
               else
                   TonalPalette(seed_hue, SECONDARY_CHROMA)
               end,
        :T  => if tertiary !== nothing
                   tp = tonal_palette(tertiary)
                   TonalPalette(tp.hue, tp.chroma)
               else
                   TonalPalette(_sanitize_degrees(seed_hue + TERTIARY_HUE_OFFSET),
                                TERTIARY_CHROMA)
               end,
        :N  => TonalPalette(seed_hue, NEUTRAL_CHROMA),
        :NV => TonalPalette(seed_hue, NEUTRAL_VARIANT_CHROMA),
        :E  => TonalPalette(ERROR_HUE, ERROR_CHROMA),
    )

    # Map each role to its hex value
    result = Dict{Symbol,String}()
    for (role_name, (palette_sym, light_tone, dark_tone)) in pairs(ROLE_MAPPING)
        palette = palettes[palette_sym]
        tone = dark ? dark_tone : light_tone
        result[role_name] = palette[tone]
    end

    result
end

"""
    color_scheme_pair(seed; secondary=nothing, tertiary=nothing,
                      contrast=:standard) → (light, dark)

Generate both light and dark color schemes in one call.
Returns a tuple of `(light_scheme, dark_scheme)`.
"""
function color_scheme_pair(seed::AbstractString;
                           secondary::Union{AbstractString,Nothing} = nothing,
                           tertiary::Union{AbstractString,Nothing} = nothing,
                           contrast::Symbol = :standard)
    light = color_scheme(seed; dark=false, secondary, tertiary, contrast)
    dark  = color_scheme(seed; dark=true,  secondary, tertiary, contrast)
    (light, dark)
end
