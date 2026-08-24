#=
HCT (Hue, Chroma, Tone) color space implementation.

Ported to Julia from Google's material-color-utilities.
Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0.
https://github.com/material-foundation/material-color-utilities

See LICENSES_THIRD_PARTY.md for the full Apache 2.0 license text.

This file has been substantially modified from the original TypeScript/Dart
sources: rewritten in Julia with StaticArrays, adapted to Julia conventions,
and restructured into the MaterialDocs.jl module.

HCT combines CAM16's hue and chroma with CIELAB's L* (lightness) as the
tone axis. This makes tone perceptually uniform — a tone-40 blue looks
equally dark as a tone-40 yellow — enabling systematic assignment of
tones to color roles with guaranteed contrast ratios.
=#

# ─────────────────────────────────────────────────────────────────────────────
# Types
# ─────────────────────────────────────────────────────────────────────────────

"""
    HCT

A color in the HCT (Hue, Chroma, Tone) perceptual color space.

# Fields
- `hue::Float64`: 0–360 (circular). The perceived color on the color wheel.
- `chroma::Float64`: 0–~113 (gamut-dependent max). Saturation intensity.
- `tone::Float64`: 0 (black)–100 (white). Perceptual lightness (CIE L*).
"""
struct HCT
    hue::Float64
    chroma::Float64
    tone::Float64
end

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

# sRGB ↔ XYZ conversion matrices (D65, [0,100] scale)
const SRGB_TO_XYZ = SA_F64[
    0.41233895  0.35762064  0.18051042;
    0.21265174  0.71515870  0.07218957;
    0.01933080  0.11919552  0.95056300
]

const XYZ_TO_SRGB = SA_F64[
    3.2413774792388685  -1.5376652402851851  -0.49885366846268053;
   -0.9691452513005321   1.8758853451067872   0.04156585616912061;
    0.05562093689691305 -0.20395524564742123   1.0571799993703593
]

# CAM16 M16 matrix (Hunt-Pointer-Estévez chromatic adaptation)
const M16 = SA_F64[
    0.401288   0.650173  -0.051461;
   -0.250268   1.204414   0.045854;
   -0.002079   0.048952   0.953127
]

const M16_INV = SA_F64[
    1.86206786  -1.01125463   0.14918677;
    0.38752654   0.62144744  -0.00897398;
   -0.01584150  -0.03412294   1.04996444
]

# D65 white point in XYZ (Y = 100)
const WHITE_POINT_D65 = SA_F64[95.047, 100.0, 108.883]

# Row of SRGB_TO_XYZ that gives Y (luminance) from linear RGB
const Y_FROM_LINRGB = SA_F64[0.2126, 0.7152, 0.0722]

# ─────────────────────────────────────────────────────────────────────────────
# sRGB Utilities
# ─────────────────────────────────────────────────────────────────────────────

"""Linearize an sRGB integer component (0–255) → linear [0, 100]."""
function _linearize(rgb::Int)::Float64
    normalized = rgb / 255.0
    if normalized <= 0.040449936
        normalized / 12.92 * 100.0
    else
        ((normalized + 0.055) / 1.055)^2.4 * 100.0
    end
end

"""Delinearize a linear component [0, 100] → sRGB integer (0–255)."""
function _delinearize(component::Float64)::Int
    normalized = component / 100.0
    delinearized = if normalized <= 0.0031308
        normalized * 12.92
    else
        1.055 * normalized^(1.0 / 2.4) - 0.055
    end
    clamp(round(Int, delinearized * 255.0), 0, 255)
end

"""
Delinearize to a Float64 sRGB value (0–255), without rounding/clamping.
Used by the HCT solver for precise gamut boundary operations.
"""
function _true_delinearize(component::Float64)::Float64
    normalized = component / 100.0
    delinearized = if normalized <= 0.0031308
        normalized * 12.92
    else
        1.055 * normalized^(1.0 / 2.4) - 0.055
    end
    delinearized * 255.0
end

"""Parse a hex color string (#RRGGBB or RRGGBB) to (r, g, b) integers."""
function _parse_hex(hex::AbstractString)::NTuple{3,Int}
    s = lstrip(hex, '#')
    length(s) == 6 || throw(ArgumentError("Expected 6-character hex string, got \"$hex\""))
    r = parse(Int, s[1:2]; base=16)
    g = parse(Int, s[3:4]; base=16)
    b = parse(Int, s[5:6]; base=16)
    (r, g, b)
end

"""Convert (r, g, b) integers to a #RRGGBB hex string."""
function _to_hex_string(r::Int, g::Int, b::Int)::String
    string('#',
        uppercase(string(r; base=16, pad=2)),
        uppercase(string(g; base=16, pad=2)),
        uppercase(string(b; base=16, pad=2)))
end

# ─────────────────────────────────────────────────────────────────────────────
# CIE L* (Tone) ↔ Y (Luminance)
# ─────────────────────────────────────────────────────────────────────────────

"""Convert CIE Y luminance [0, 100] to CIE L* lightness [0, 100]."""
function _lstar_from_y(y::Float64)::Float64
    y_normalized = y / 100.0
    if y_normalized <= 216.0 / 24389.0  # (6/29)^3
        y_normalized * (24389.0 / 27.0)
    else
        116.0 * cbrt(y_normalized) - 16.0
    end
end

"""Convert CIE L* lightness [0, 100] to CIE Y luminance [0, 100]."""
function _y_from_lstar(lstar::Float64)::Float64
    if lstar > 8.0
        ((lstar + 16.0) / 116.0)^3 * 100.0
    else
        lstar / (24389.0 / 27.0) * 100.0
    end
end

"""Convert a CIE L* tone to an sRGB grey (r, g, b) tuple."""
function _srgb_from_tone(tone::Float64)::NTuple{3,Int}
    y = _y_from_lstar(tone)
    component = _delinearize(y)
    (component, component, component)
end

"""Convert sRGB (r, g, b) integers to CIE L* tone."""
function _tone_from_srgb(r::Int, g::Int, b::Int)::Float64
    lin_r = _linearize(r)
    lin_g = _linearize(g)
    lin_b = _linearize(b)
    y = Y_FROM_LINRGB[1] * lin_r + Y_FROM_LINRGB[2] * lin_g + Y_FROM_LINRGB[3] * lin_b
    _lstar_from_y(y)
end

# ─────────────────────────────────────────────────────────────────────────────
# CAM16 Viewing Conditions
# ─────────────────────────────────────────────────────────────────────────────

"""
    ViewingConditions

Precomputed parameters for the CAM16 color appearance model under specific
viewing conditions. The DEFAULT constant uses standard sRGB conditions
(D65, 11.725 cd/m² adapting luminance, average surround).
"""
struct ViewingConditions
    n::Float64       # Yb/Yw (background luminance ratio)
    aw::Float64      # adapted white achromatic response
    nbb::Float64     # brightness induction factor
    ncb::Float64     # chromatic induction factor
    c::Float64       # exponential nonlinearity
    nc::Float64      # chromatic adaptation factor
    fl::Float64      # luminance-level adaptation factor
    fl_root::Float64 # fl^0.25
    z::Float64       # base exponential nonlinearity
    rgb_d::SVector{3,Float64}  # degree of chromatic adaptation per channel
end

function _make_viewing_conditions(;
    white_point::SVector{3,Float64} = WHITE_POINT_D65,
    adapting_luminance::Float64 = (200.0 / π) * _y_from_lstar(50.0) / 100.0,
    background_lstar::Float64 = 50.0,
    surround::Float64 = 2.0,
    discounting_illuminant::Bool = false,
)::ViewingConditions
    # M16-adapted white point
    rW = M16[1, 1] * white_point[1] + M16[1, 2] * white_point[2] + M16[1, 3] * white_point[3]
    gW = M16[2, 1] * white_point[1] + M16[2, 2] * white_point[2] + M16[2, 3] * white_point[3]
    bW = M16[3, 1] * white_point[1] + M16[3, 2] * white_point[2] + M16[3, 3] * white_point[3]

    # Surround parameters
    f = 0.8 + surround / 10.0
    c_param = if f >= 0.9
        _lerp(0.59, 0.69, (f - 0.9) * 10.0)
    else
        _lerp(0.525, 0.59, (f - 0.8) * 10.0)
    end
    nc = f

    # Degree of adaptation
    d = if discounting_illuminant
        1.0
    else
        clamp(f * (1.0 - (1.0 / 3.6) * exp((-adapting_luminance - 42.0) / 92.0)), 0.0, 1.0)
    end

    # Chromatic adaptation factors
    rgb_d = SA_F64[
        d * (100.0 / rW) + 1.0 - d,
        d * (100.0 / gW) + 1.0 - d,
        d * (100.0 / bW) + 1.0 - d,
    ]

    # Luminance-level adaptation factor
    k = 1.0 / (5.0 * adapting_luminance + 1.0)
    k4 = k^4
    k4f = 1.0 - k4
    fl = k4 * adapting_luminance + 0.1 * k4f * k4f * cbrt(5.0 * adapting_luminance)

    # Background parameters
    n = _y_from_lstar(background_lstar) / white_point[2]
    z = 1.48 + sqrt(n)
    nbb = 0.725 / n^0.2
    ncb = nbb

    # Adapted white achromatic response
    rW_adapted = rgb_d[1] * rW
    gW_adapted = rgb_d[2] * gW
    bW_adapted = rgb_d[3] * bW

    rW_af = (fl * abs(rW_adapted) / 100.0)^0.42
    gW_af = (fl * abs(gW_adapted) / 100.0)^0.42
    bW_af = (fl * abs(bW_adapted) / 100.0)^0.42

    rW_a = sign(rW_adapted) * 400.0 * rW_af / (rW_af + 27.13)
    gW_a = sign(gW_adapted) * 400.0 * gW_af / (gW_af + 27.13)
    bW_a = sign(bW_adapted) * 400.0 * bW_af / (bW_af + 27.13)

    aw = (2.0 * rW_a + gW_a + 0.05 * bW_a - 0.305) * nbb
    fl_root = fl^0.25

    ViewingConditions(n, aw, nbb, ncb, c_param, nc, fl, fl_root, z, rgb_d)
end

_lerp(a::Float64, b::Float64, t::Float64) = a + (b - a) * t

const DEFAULT_VC = _make_viewing_conditions()

# ─────────────────────────────────────────────────────────────────────────────
# CAM16 Color Appearance Model
# ─────────────────────────────────────────────────────────────────────────────

"""
    CAM16

Attributes from the CAM16 color appearance model.
"""
struct CAM16
    hue::Float64      # h: hue angle in degrees [0, 360)
    chroma::Float64   # C: chroma
    j::Float64        # J: lightness
    q::Float64        # Q: brightness
    m::Float64        # M: colorfulness
    s::Float64        # s: saturation
end

"""Compute CAM16 attributes from sRGB (r, g, b) integers."""
function _cam16_from_srgb(r::Int, g::Int, b::Int, vc::ViewingConditions=DEFAULT_VC)::CAM16
    # Linearize sRGB
    red_l = _linearize(r)
    green_l = _linearize(g)
    blue_l = _linearize(b)

    # sRGB → XYZ
    x = SRGB_TO_XYZ[1, 1] * red_l + SRGB_TO_XYZ[1, 2] * green_l + SRGB_TO_XYZ[1, 3] * blue_l
    y = SRGB_TO_XYZ[2, 1] * red_l + SRGB_TO_XYZ[2, 2] * green_l + SRGB_TO_XYZ[2, 3] * blue_l
    z = SRGB_TO_XYZ[3, 1] * red_l + SRGB_TO_XYZ[3, 2] * green_l + SRGB_TO_XYZ[3, 3] * blue_l

    # XYZ → M16 (sharpened RGB)
    rC = M16[1, 1] * x + M16[1, 2] * y + M16[1, 3] * z
    gC = M16[2, 1] * x + M16[2, 2] * y + M16[2, 3] * z
    bC = M16[3, 1] * x + M16[3, 2] * y + M16[3, 3] * z

    # Chromatic adaptation
    rD = vc.rgb_d[1] * rC
    gD = vc.rgb_d[2] * gC
    bD = vc.rgb_d[3] * bC

    # Non-linear response compression
    rAF = (vc.fl * abs(rD) / 100.0)^0.42
    gAF = (vc.fl * abs(gD) / 100.0)^0.42
    bAF = (vc.fl * abs(bD) / 100.0)^0.42

    rA = sign(rD) * 400.0 * rAF / (rAF + 27.13)
    gA = sign(gD) * 400.0 * gAF / (gAF + 27.13)
    bA = sign(bD) * 400.0 * bAF / (bAF + 27.13)

    # Opponent color dimensions
    a = (11.0 * rA - 12.0 * gA + bA) / 11.0
    b_opp = (rA + gA - 2.0 * bA) / 9.0

    # Hue
    hue_rad = atan(b_opp, a)
    hue_deg = hue_rad * 180.0 / π
    hue = if hue_deg < 0
        hue_deg + 360.0
    elseif hue_deg >= 360.0
        hue_deg - 360.0
    else
        hue_deg
    end

    # Achromatic response
    u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0
    p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0
    ac = p2 * vc.nbb

    # CAM16 J (lightness)
    j = 100.0 * (ac / vc.aw)^(vc.c * vc.z)

    # CAM16 Q (brightness)
    q = (4.0 / vc.c) * sqrt(j / 100.0) * (vc.aw + 4.0) * vc.fl_root

    # Eccentricity factor
    hue_prime = hue < 20.14 ? hue + 360.0 : hue
    eHue = 0.25 * (cos(hue_prime * π / 180.0 + 2.0) + 3.8)

    # Chromatic content
    p1 = 50000.0 / 13.0 * eHue * vc.nc * vc.ncb
    t = p1 * sqrt(a * a + b_opp * b_opp) / (u + 0.305)
    alpha = t^0.9 * (1.64 - 0.29^vc.n)^0.73

    # CAM16 C (chroma), M (colorfulness), s (saturation)
    c_val = alpha * sqrt(j / 100.0)
    m = c_val * vc.fl_root
    s = 50.0 * sqrt(alpha * vc.c / (vc.aw + 4.0))

    CAM16(hue, c_val, j, q, m, s)
end

"""Compute XYZ from CAM16 J, C, h via inverse model."""
function _xyz_from_cam16(j::Float64, c::Float64, h::Float64,
                         vc::ViewingConditions=DEFAULT_VC)::SVector{3,Float64}
    hue_rad = h * π / 180.0

    alpha = if c == 0.0 || j == 0.0
        0.0
    else
        c / sqrt(j / 100.0)
    end

    t = (alpha / (1.64 - 0.29^vc.n)^0.73)^(1.0 / 0.9)
    eHue = 0.25 * (cos(hue_rad + 2.0) + 3.8)
    ac = vc.aw * (j / 100.0)^(1.0 / (vc.c * vc.z))
    p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
    p2 = ac / vc.nbb

    hSin = sin(hue_rad)
    hCos = cos(hue_rad)

    gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin)
    a = gamma * hCos
    b = gamma * hSin

    rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
    gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
    bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0

    rC_base = max(0.0, (27.13 * abs(rA)) / (400.0 - abs(rA)))
    gC_base = max(0.0, (27.13 * abs(gA)) / (400.0 - abs(gA)))
    bC_base = max(0.0, (27.13 * abs(bA)) / (400.0 - abs(bA)))

    rC = sign(rA) * (100.0 / vc.fl) * rC_base^(1.0 / 0.42)
    gC = sign(gA) * (100.0 / vc.fl) * gC_base^(1.0 / 0.42)
    bC = sign(bA) * (100.0 / vc.fl) * bC_base^(1.0 / 0.42)

    rF = rC / vc.rgb_d[1]
    gF = gC / vc.rgb_d[2]
    bF = bC / vc.rgb_d[3]

    x = M16_INV[1, 1] * rF + M16_INV[1, 2] * gF + M16_INV[1, 3] * bF
    y = M16_INV[2, 1] * rF + M16_INV[2, 2] * gF + M16_INV[2, 3] * bF
    z = M16_INV[3, 1] * rF + M16_INV[3, 2] * gF + M16_INV[3, 3] * bF

    SA_F64[x, y, z]
end

# ─────────────────────────────────────────────────────────────────────────────
# HCT Solver
#
# Finds the sRGB color matching a given (hue, chroma, tone) in HCT space.
# Uses analytical solution via Newton's method with gamut-boundary fallback.
# ─────────────────────────────────────────────────────────────────────────────

# Precomputed matrices for the solver (combine M16, chromatic adaptation,
# and sRGB conversion into single matrix operations for efficiency).
# These are computed for DEFAULT_VC and are constants.

const SCALED_DISCOUNT_FROM_LINRGB = SA_F64[
    0.001200833568784504   0.002389694492170889   0.0002795742885861124;
    0.0005891086651375999  0.0029785502573438758  0.0003270666104008398;
    0.00010146692491640572 0.0005364214359186694  0.0032979401770712076
]

const LINRGB_FROM_SCALED_DISCOUNT = SA_F64[
    1373.2198709594231   -1100.4251190754821  -7.278681089101213;
    -271.815969077903      559.6580465940733  -32.46047482791194;
       1.9622899599665666  -57.173814538844006 308.7233197812385
]

# Critical planes: linearized sRGB values at half-integer sRGB positions.
# Used for efficient binary search of the gamut boundary.
const CRITICAL_PLANES = let
    planes = Vector{Float64}(undef, 256)
    for i in 0:255
        normalized = (i + 0.5) / 255.0
        planes[i + 1] = if normalized <= 0.040449936
            normalized / 12.92 * 100.0
        else
            ((normalized + 0.055) / 1.055)^2.4 * 100.0
        end
    end
    planes
end

"""Sanitize an angle to [0, 360)."""
function _sanitize_degrees(degrees::Float64)::Float64
    d = degrees % 360.0
    d < 0.0 ? d + 360.0 : d
end

"""Chromatic adaptation for the solver (omits fl scaling vs full CAM16)."""
function _chromatic_adaptation(component::Float64)::Float64
    af = abs(component)^0.42
    sign(component) * 400.0 * af / (af + 27.13)
end

"""Inverse chromatic adaptation for the solver."""
function _inverse_chromatic_adaptation(adapted::Float64)::Float64
    adapted_abs = abs(adapted)
    base = max(0.0, 27.13 * adapted_abs / (400.0 - adapted_abs))
    sign(adapted) * base^(1.0 / 0.42)
end

"""Compute hue (in radians) of a linear RGB color via the solver's path."""
function _hue_of(linrgb::SVector{3,Float64})::Float64
    # linrgb → scaled discount space
    sd1 = SCALED_DISCOUNT_FROM_LINRGB[1, 1] * linrgb[1] +
          SCALED_DISCOUNT_FROM_LINRGB[1, 2] * linrgb[2] +
          SCALED_DISCOUNT_FROM_LINRGB[1, 3] * linrgb[3]
    sd2 = SCALED_DISCOUNT_FROM_LINRGB[2, 1] * linrgb[1] +
          SCALED_DISCOUNT_FROM_LINRGB[2, 2] * linrgb[2] +
          SCALED_DISCOUNT_FROM_LINRGB[2, 3] * linrgb[3]
    sd3 = SCALED_DISCOUNT_FROM_LINRGB[3, 1] * linrgb[1] +
          SCALED_DISCOUNT_FROM_LINRGB[3, 2] * linrgb[2] +
          SCALED_DISCOUNT_FROM_LINRGB[3, 3] * linrgb[3]

    rA = _chromatic_adaptation(sd1)
    gA = _chromatic_adaptation(sd2)
    bA = _chromatic_adaptation(sd3)

    a = (11.0 * rA - 12.0 * gA + bA) / 11.0
    b = (rA + gA - 2.0 * bA) / 9.0
    atan(b, a)
end

"""Check if three hue angles are in cyclic order."""
function _are_in_cyclic_order(a::Float64, b::Float64, c::Float64)::Bool
    delta_ab = _sanitize_degrees(b - a)
    delta_ac = _sanitize_degrees(c - a)
    delta_ab < delta_ac
end

"""Check if value is in [0, 100] gamut range (for linear RGB)."""
_is_bounded(x::Float64) = 0.0 <= x <= 100.0

"""
Find the n-th vertex of the sRGB gamut boundary at a given Y luminance.
There are 12 candidate vertices (4 per primary axis).
Returns (-1, -1, -1) if the vertex is out of gamut.
"""
function _nth_vertex(y::Float64, n::Int)::SVector{3,Float64}
    kR = Y_FROM_LINRGB[1]
    kG = Y_FROM_LINRGB[2]
    kB = Y_FROM_LINRGB[3]

    coord_a = (n % 4 <= 1) ? 0.0 : 100.0
    coord_b = (n % 2 == 0) ? 0.0 : 100.0

    if n < 4
        # Solve for R: g = coord_a, b = coord_b
        r = (y - coord_a * kG - coord_b * kB) / kR
        return _is_bounded(r) ? SA_F64[r, coord_a, coord_b] : SA_F64[-1.0, -1.0, -1.0]
    elseif n < 8
        # Solve for G: b = coord_a, r = coord_b
        g = (y - coord_b * kR - coord_a * kB) / kG
        return _is_bounded(g) ? SA_F64[coord_b, g, coord_a] : SA_F64[-1.0, -1.0, -1.0]
    else
        # Solve for B: r = coord_a, g = coord_b
        b = (y - coord_a * kR - coord_b * kG) / kB
        return _is_bounded(b) ? SA_F64[coord_a, coord_b, b] : SA_F64[-1.0, -1.0, -1.0]
    end
end

"""Set one axis of a linear-interpolated point to a specific value."""
function _set_coordinate(source::SVector{3,Float64}, coordinate::Float64,
                         target::SVector{3,Float64}, axis::Int)::SVector{3,Float64}
    t = (coordinate - source[axis]) / (target[axis] - source[axis])
    SA_F64[
        source[1] + (target[1] - source[1]) * t,
        source[2] + (target[2] - source[2]) * t,
        source[3] + (target[3] - source[3]) * t,
    ]
end

"""
Find the two gamut boundary vertices that bracket the target hue at given Y.
Returns (left, right) linear RGB vectors.
"""
function _bisect_to_segment(y::Float64, target_hue::Float64)
    left = SA_F64[-1.0, -1.0, -1.0]
    right = SA_F64[-1.0, -1.0, -1.0]
    left_hue = 0.0
    right_hue = 0.0
    initialized = false
    uncut = true

    for n in 0:11
        mid = _nth_vertex(y, n)
        mid[1] < 0 && continue

        mid_hue = _hue_of(mid)
        if !initialized
            left = mid
            right = mid
            left_hue = mid_hue
            right_hue = mid_hue
            initialized = true
            continue
        end

        if uncut || _are_in_cyclic_order(left_hue * 180.0 / π,
                                          mid_hue * 180.0 / π,
                                          right_hue * 180.0 / π)
            uncut = false
            if _are_in_cyclic_order(left_hue * 180.0 / π,
                                     target_hue * 180.0 / π,
                                     mid_hue * 180.0 / π)
                right = mid
                right_hue = mid_hue
            else
                left = mid
                left_hue = mid_hue
            end
        end
    end

    (left, right)
end

"""
Binary search within the gamut to find the maximum-chroma color at given
Y and target hue. Returns linear RGB in [0, 100].
"""
function _bisect_to_limit(y::Float64, target_hue::Float64)::SVector{3,Float64}
    segment = _bisect_to_segment(y, target_hue)
    left = segment[1]
    left_hue = _hue_of(left)
    right = segment[2]

    for axis in 1:3
        if left[axis] != right[axis]
            if left[axis] < right[axis]
                l_plane = floor(Int, _true_delinearize(left[axis]) - 0.5)
                r_plane = ceil(Int, _true_delinearize(right[axis]) - 0.5)
            else
                l_plane = ceil(Int, _true_delinearize(left[axis]) - 0.5)
                r_plane = floor(Int, _true_delinearize(right[axis]) - 0.5)
            end

            for _ in 1:8
                abs(r_plane - l_plane) <= 1 && break

                m_plane = (l_plane + r_plane) ÷ 2
                mid_coord = CRITICAL_PLANES[clamp(m_plane + 1, 1, 256)]

                mid = _set_coordinate(left, mid_coord, right, axis)
                mid_hue = _hue_of(mid)

                if _are_in_cyclic_order(left_hue * 180.0 / π,
                                         target_hue * 180.0 / π,
                                         mid_hue * 180.0 / π)
                    right = mid
                    r_plane = m_plane
                else
                    left = mid
                    left_hue = mid_hue
                    l_plane = m_plane
                end
            end
        end
    end

    # Return midpoint of the converged bracket
    SA_F64[
        (left[1] + right[1]) / 2.0,
        (left[2] + right[2]) / 2.0,
        (left[3] + right[3]) / 2.0,
    ]
end

"""
Try to find an exact sRGB match for (hue, chroma, Y) via Newton's method
on CAM16 J. Returns (r, g, b) integers if found, or `nothing` if out of gamut.
"""
function _find_result_by_j(hue_rad::Float64, chroma::Float64,
                            y::Float64)::Union{NTuple{3,Int},Nothing}
    # Initial J estimate
    j = sqrt(y) * 11.0

    vc = DEFAULT_VC
    t_inner_coeff = 1.0 / (1.64 - 0.29^vc.n)^0.73
    eHue = 0.25 * (cos(hue_rad + 2.0) + 3.8)
    p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
    hSin = sin(hue_rad)
    hCos = cos(hue_rad)

    for iteration in 0:4
        j_normalized = j / 100.0
        alpha = (chroma == 0.0 || j == 0.0) ? 0.0 : chroma / sqrt(j_normalized)

        t = (alpha * t_inner_coeff)^(1.0 / 0.9)
        ac = vc.aw * j_normalized^(1.0 / (vc.c * vc.z))
        p2 = ac / vc.nbb

        gamma = 23.0 * (p2 + 0.305) * t /
                (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin)
        a = gamma * hCos
        b = gamma * hSin

        rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
        gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
        bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0

        rC_scaled = _inverse_chromatic_adaptation(rA)
        gC_scaled = _inverse_chromatic_adaptation(gA)
        bC_scaled = _inverse_chromatic_adaptation(bA)

        # Convert to linear sRGB via precomputed combined matrix.
        # LINRGB_FROM_SCALED_DISCOUNT already incorporates the rgb_d
        # inverse, so we pass scaled-discount values directly.
        lin_r = LINRGB_FROM_SCALED_DISCOUNT[1, 1] * rC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[1, 2] * gC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[1, 3] * bC_scaled
        lin_g = LINRGB_FROM_SCALED_DISCOUNT[2, 1] * rC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[2, 2] * gC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[2, 3] * bC_scaled
        lin_b = LINRGB_FROM_SCALED_DISCOUNT[3, 1] * rC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[3, 2] * gC_scaled +
                LINRGB_FROM_SCALED_DISCOUNT[3, 3] * bC_scaled

        # Check gamut
        (lin_r < 0 || lin_g < 0 || lin_b < 0) && return nothing

        fnj = Y_FROM_LINRGB[1] * lin_r + Y_FROM_LINRGB[2] * lin_g + Y_FROM_LINRGB[3] * lin_b
        fnj <= 0 && return nothing

        if iteration == 4 || abs(fnj - y) < 0.002
            (lin_r > 100.01 || lin_g > 100.01 || lin_b > 100.01) && return nothing
            return (_delinearize(lin_r), _delinearize(lin_g), _delinearize(lin_b))
        end

        # Newton's method step
        j = j - (fnj - y) * j / (2.0 * fnj)
    end

    nothing
end

"""
    _solve_to_srgb(hue, chroma, tone) → (r, g, b)

Find the sRGB color that best represents the given HCT coordinates.
Returns integer (r, g, b) in [0, 255].
"""
function _solve_to_srgb(hue::Float64, chroma::Float64, tone::Float64)::NTuple{3,Int}
    # Edge cases: near-achromatic or extreme tones
    if chroma < 1.0 || tone < 1.0 || tone > 99.0
        return _srgb_from_tone(tone)
    end

    hue_deg = _sanitize_degrees(hue)
    hue_rad = hue_deg / 180.0 * π
    y = _y_from_lstar(tone)

    # Try analytical solution first
    exact = _find_result_by_j(hue_rad, chroma, y)
    exact !== nothing && return exact

    # Fall back to gamut-boundary bisection (maximum achievable chroma)
    linrgb = _bisect_to_limit(y, hue_rad)
    return (_delinearize(linrgb[1]), _delinearize(linrgb[2]), _delinearize(linrgb[3]))
end

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

"""
    hct(hex::AbstractString) → HCT

Parse a hex color string (e.g. `"#6750A4"`) to the HCT color space.

# Examples
```julia
c = hct("#6750A4")
# HCT(281.8, 46.3, 40.0)  (approximately)
```
"""
function hct(hex::AbstractString)::HCT
    r, g, b = _parse_hex(hex)
    cam = _cam16_from_srgb(r, g, b)
    tone = _tone_from_srgb(r, g, b)
    HCT(cam.hue, cam.chroma, tone)
end

"""
    HCT(hue, chroma, tone)

Construct an HCT color. Values are stored as-is; use `to_hex` to convert
to sRGB (which may gamut-map the chroma if needed).
"""
HCT(hue::Real, chroma::Real, tone::Real) =
    HCT(Float64(hue), Float64(chroma), Float64(tone))

"""
    to_hex(c::HCT) → String

Convert an HCT color to the closest sRGB hex string (`"#RRGGBB"`).
If the requested chroma is not achievable in sRGB, the maximum achievable
chroma at the given hue and tone is used instead.

# Examples
```julia
to_hex(HCT(281.8, 46.3, 40.0))  # "#6750A4" (approximately)
```
"""
function to_hex(c::HCT)::String
    r, g, b = _solve_to_srgb(c.hue, c.chroma, c.tone)
    _to_hex_string(r, g, b)
end

function Base.show(io::IO, c::HCT)
    print(io, "HCT(hue=", round(c.hue; digits=1),
              ", chroma=", round(c.chroma; digits=1),
              ", tone=", round(c.tone; digits=1), ")")
end
