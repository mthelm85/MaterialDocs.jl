module MaterialDocs

using MaterialColors
import Documenter
import MarkdownAST

# ─────────────────────────────────────────────────────────────────────────────
# Color engine (Phase 1)
# ─────────────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────────────
# Theme system (Phase 2)
# ─────────────────────────────────────────────────────────────────────────────

include("themes/theme_config.jl")
include("themes/builtin.jl")
include("themes/toml.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Writer (Phase 2)
# ─────────────────────────────────────────────────────────────────────────────

include("writer/nav.jl")
include("writer/writer.jl")
include("writer/domify.jl")
include("writer/page.jl")
include("writer/render.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Theme Editor (Phase 8)
# ─────────────────────────────────────────────────────────────────────────────

include("editor/editor.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

# Types
export ThemeConfig, Material3


# Theme functions
export resolve_theme, BUILTIN_THEMES
export load_theme, save_theme, find_theme_toml

# Editor
export editor

end
