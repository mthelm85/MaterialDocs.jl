#=
WCAG Contrast Utilities

Provides functions for checking and computing WCAG 2.1 contrast ratios
between colors, ensuring accessibility compliance in generated themes.
=#

"""
    contrast_ratio(hex1::AbstractString, hex2::AbstractString) → Float64

Compute the WCAG 2.1 contrast ratio between two hex colors.
Returns a value in [1, 21]. A ratio ≥ 4.5 meets WCAG AA for normal text;
≥ 3.0 meets AA for large text; ≥ 7.0 meets AAA.

# Examples
```julia
contrast_ratio("#000000", "#FFFFFF")  # 21.0
contrast_ratio("#6750A4", "#FFFFFF")  # ≈ 5.3
```
"""
function contrast_ratio(hex1::AbstractString, hex2::AbstractString)::Float64
    l1 = _relative_luminance(hex1)
    l2 = _relative_luminance(hex2)
    lighter = max(l1, l2)
    darker  = min(l1, l2)
    (lighter + 0.05) / (darker + 0.05)
end

"""
    contrast_ratio(tone1::Float64, tone2::Float64) → Float64

Compute contrast ratio from two CIE L* tone values (0–100).
Useful for checking contrast between HCT tones without converting to hex.
"""
function contrast_ratio(tone1::Float64, tone2::Float64)::Float64
    l1 = _relative_luminance_from_tone(tone1)
    l2 = _relative_luminance_from_tone(tone2)
    lighter = max(l1, l2)
    darker  = min(l1, l2)
    (lighter + 0.05) / (darker + 0.05)
end

"""
    meets_aa(hex_fg::AbstractString, hex_bg::AbstractString;
             large_text::Bool=false) → Bool

Check if a foreground/background color pair meets WCAG 2.1 AA contrast
requirements. Normal text requires ≥ 4.5:1; large text requires ≥ 3.0:1.
"""
function meets_aa(hex_fg::AbstractString, hex_bg::AbstractString;
                  large_text::Bool = false)::Bool
    threshold = large_text ? 3.0 : 4.5
    contrast_ratio(hex_fg, hex_bg) >= threshold
end

"""
    meets_aaa(hex_fg::AbstractString, hex_bg::AbstractString;
              large_text::Bool=false) → Bool

Check if a foreground/background color pair meets WCAG 2.1 AAA contrast
requirements. Normal text requires ≥ 7.0:1; large text requires ≥ 4.5:1.
"""
function meets_aaa(hex_fg::AbstractString, hex_bg::AbstractString;
                   large_text::Bool = false)::Bool
    threshold = large_text ? 4.5 : 7.0
    contrast_ratio(hex_fg, hex_bg) >= threshold
end

"""
    lighter_tone(tone::Float64, ratio::Float64) → Float64

Find the lightest tone (in CIE L*) that achieves at least the given
contrast ratio against the input tone. Returns `NaN` if impossible.
"""
function lighter_tone(tone::Float64, ratio::Float64)::Float64
    # Dark tone is the input, we want lighter
    dark_y = _y_from_lstar(tone) / 100.0
    light_y = ratio * (dark_y + 0.05) - 0.05
    (light_y < 0.0 || light_y > 1.0) && return NaN
    _lstar_from_y(light_y * 100.0)
end

"""
    darker_tone(tone::Float64, ratio::Float64) → Float64

Find the darkest tone (in CIE L*) that achieves at least the given
contrast ratio against the input tone. Returns `NaN` if impossible.
"""
function darker_tone(tone::Float64, ratio::Float64)::Float64
    # Light tone is the input, we want darker
    light_y = _y_from_lstar(tone) / 100.0
    dark_y = (light_y + 0.05) / ratio - 0.05
    (dark_y < 0.0 || dark_y > 1.0) && return NaN
    _lstar_from_y(dark_y * 100.0)
end

# ─────────────────────────────────────────────────────────────────────────────
# Internal
# ─────────────────────────────────────────────────────────────────────────────

"""Relative luminance (Y/Yn in [0, 1]) from a hex color."""
function _relative_luminance(hex::AbstractString)::Float64
    r, g, b = _parse_hex(hex)
    lin_r = _linearize(r) / 100.0
    lin_g = _linearize(g) / 100.0
    lin_b = _linearize(b) / 100.0
    0.2126 * lin_r + 0.7152 * lin_g + 0.0722 * lin_b
end

"""Relative luminance from a CIE L* tone value."""
function _relative_luminance_from_tone(tone::Float64)::Float64
    _y_from_lstar(tone) / 100.0
end
