module MaterialDocs

using StaticArrays

# ─────────────────────────────────────────────────────────────────────────────
# Color engine (Phase 1)
# ─────────────────────────────────────────────────────────────────────────────

include("color/hct.jl")
include("color/tonal_palette.jl")
include("color/color_scheme.jl")
include("color/contrast.jl")

# Public types
export HCT, TonalPalette

# Public functions — color
export hct, to_hex
export tonal_palette, tone_at, precompute!
export color_scheme, color_scheme_pair
export contrast_ratio, meets_aa, meets_aaa
export lighter_tone, darker_tone

end
