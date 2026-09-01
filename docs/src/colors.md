```@meta
CurrentModule = MaterialDocs
```

# Color Engine

MaterialDocs contains a pure-Julia port of Google's
[material-color-utilities](https://github.com/material-foundation/material-color-utilities).
It is used to build themes, but it is a general-purpose color library and is
exported for direct use.

## HCT

HCT combines the hue and chroma of the CAM16 color appearance model with the
lightness (`L*`) of CIELAB. Its value is that **tone maps directly to contrast**:
two colors 40 tones apart have a predictable contrast ratio regardless of hue.
That is what lets a whole palette be generated from one color without hand-tuning.

```jldoctest
julia> using MaterialDocs

julia> c = hct("#6750A4")
HCT(hue=299.0, chroma=48.2, tone=40.1)

julia> to_hex(c)
"#6750A4"
```

Construct one from values with [`HCT`](@ref):

```julia
HCT(299.0, 48.2, 40.0)
```

Not every hue/chroma pair exists at every tone — the sRGB gamut narrows toward
black and white. Requests outside it are resolved to the closest in-gamut color,
so round-tripping a saturated color at an extreme tone may not return the exact
input.

## Tonal palettes

A [`TonalPalette`](@ref) is one hue and chroma sampled across the full tone range:

```julia
p = tonal_palette("#6750A4")
tone_at(p, 40)   # the primary color in a light scheme
tone_at(p, 80)   # the primary color in a dark scheme
tone_at(p, 90)   # a light primary container
```

Tones are cached as requested; [`precompute!`](@ref) fills the standard MD3 stops
in one pass.

## Color schemes

[`color_scheme`](@ref) generates the full set of 34 MD3 roles from a seed:

```julia
light = color_scheme("#6750A4")
dark  = color_scheme("#6750A4"; dark = true)

light[:primary]
light[:on_primary_container]
light[:surface]
```

[`color_scheme_pair`](@ref) returns both at once, which is what the writer uses:

```julia
light, dark = color_scheme_pair("#6750A4")
```

Roles are derived by fixed rules: secondary shares the seed hue at chroma 16,
tertiary rotates 60° at chroma 24, neutrals hold the seed hue at very low chroma,
and error is a fixed red. Each role is then placed at the tone the MD3 spec
assigns it for that mode.

## Contrast

```julia
contrast_ratio("#FFFFFF", "#6750A4")   # 6.44
meets_aa("#FFFFFF", "#6750A4")         # true
meets_aaa("#FFFFFF", "#6750A4")        # false
```

[`contrast_ratio`](@ref) also accepts two tones directly, which is cheaper when
working in HCT. To find a tone meeting a target ratio against a known one, use
[`lighter_tone`](@ref) and [`darker_tone`](@ref):

```julia
lighter_tone(40.0, 4.5)   # lightest tone with 4.5:1 against tone 40
```

Both return `NaN` when the ratio is unreachable — check before using the result.

```julia
t = lighter_tone(60.0, 7.0)
isnan(t) && error("no tone meets that contrast")
```

## Generated CSS tokens

At build time each role becomes a CSS custom property, with `_` replaced by `-`:

```css
--md-sys-color-primary
--md-sys-color-on-primary-container
--md-sys-color-surface-container-high
```

All 34 are emitted regardless of whether the bundled stylesheets use them, so
custom CSS has the complete set available. Alongside them, MaterialDocs emits
typography, shape, elevation, and motion tokens — see [Configuration](@ref) for
using them from your own stylesheets.
