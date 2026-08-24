#=
Tonal Palette — a set of tones derived from a single hue/chroma pair.

Based on the tonal palette concept from Google's material-color-utilities.
Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0.
https://github.com/material-foundation/material-color-utilities
See LICENSES_THIRD_PARTY.md for the full license text.

A TonalPalette maps tone values (0–100) to hex color strings by computing
HCT(hue, chroma, tone) → sRGB for each requested tone. Results are cached
for repeated lookups.
=#

"""
    TonalPalette

A color palette derived from a single hue and chroma, generating hex colors
at any requested tone (0–100).

# Fields
- `hue::Float64`: Hue angle in degrees [0, 360).
- `chroma::Float64`: Chroma value for this palette.
- `cache::Dict{Int,String}`: Lazily populated tone → hex cache.

# Examples
```julia
p = tonal_palette("#6750A4")
p[40]   # "#6750A4" (approximately)
p[80]   # a lighter version
p[10]   # a much darker version
```
"""
mutable struct TonalPalette
    hue::Float64
    chroma::Float64
    cache::Dict{Int,String}
end

"""
    TonalPalette(hue, chroma)

Create a tonal palette from explicit hue and chroma values.
"""
TonalPalette(hue::Real, chroma::Real) =
    TonalPalette(Float64(hue), Float64(chroma), Dict{Int,String}())

"""
    tonal_palette(seed_hex::AbstractString) → TonalPalette

Create a tonal palette from a seed hex color. Extracts hue and chroma
from the seed using the HCT color space.

# Examples
```julia
p = tonal_palette("#6750A4")
p[40]  # ≈ "#6750A4"
p[90]  # light container color
```
"""
function tonal_palette(seed_hex::AbstractString)::TonalPalette
    c = hct(seed_hex)
    TonalPalette(c.hue, c.chroma)
end

"""
    getindex(p::TonalPalette, tone::Int) → String

Look up a hex color at the given tone (0–100). Results are cached.
"""
function Base.getindex(p::TonalPalette, tone::Int)::String
    get!(p.cache, tone) do
        to_hex(HCT(p.hue, p.chroma, Float64(tone)))
    end
end

"""
    tone_at(p::TonalPalette, tone::Int) → String

Alias for `p[tone]`. Returns the hex color at the given tone.
"""
tone_at(p::TonalPalette, tone::Int) = p[tone]

function Base.show(io::IO, p::TonalPalette)
    print(io, "TonalPalette(hue=", round(p.hue; digits=1),
              ", chroma=", round(p.chroma; digits=1), ")")
end

# ─────────────────────────────────────────────────────────────────────────────
# Standard tone stops used in MD3
# ─────────────────────────────────────────────────────────────────────────────

"""Standard tone stops used in Material Design 3 tonal palettes."""
const MD3_TONE_STOPS = [0, 4, 5, 6, 10, 12, 17, 20, 22, 24, 25,
                        30, 35, 40, 50, 60, 70, 75, 80, 87, 90,
                        92, 94, 95, 96, 98, 99, 100]

"""
    precompute!(p::TonalPalette)

Eagerly compute and cache all standard MD3 tone stops.
"""
function precompute!(p::TonalPalette)
    for tone in MD3_TONE_STOPS
        p[tone]  # triggers cache fill
    end
    p
end
