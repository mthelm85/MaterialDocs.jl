module MaterialDocs

using StaticArrays
import Documenter
import MarkdownAST

# ─────────────────────────────────────────────────────────────────────────────
# Color engine (Phase 1)
# ─────────────────────────────────────────────────────────────────────────────

include("color/hct.jl")
include("color/tonal_palette.jl")
include("color/color_scheme.jl")
include("color/contrast.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Theme system (Phase 2)
# ─────────────────────────────────────────────────────────────────────────────

include("themes/theme_config.jl")
include("themes/builtin.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Writer (Phase 2)
# ─────────────────────────────────────────────────────────────────────────────

include("writer/nav.jl")
include("writer/writer.jl")
include("writer/domify.jl")
include("writer/page.jl")
include("writer/render.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

# Types
export HCT, TonalPalette, ThemeConfig, Material3

# Color functions
export hct, to_hex
export tonal_palette, tone_at, precompute!
export color_scheme, color_scheme_pair
export contrast_ratio, meets_aa, meets_aaa
export lighter_tone, darker_tone

# Theme functions
export resolve_theme, BUILTIN_THEMES

end
