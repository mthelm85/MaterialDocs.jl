```@meta
CurrentModule = MaterialDocs
```

# Color Engine

Every color on a MaterialDocs site is generated at build time from a single
seed, using [MaterialColors.jl](https://github.com/mthelm85/MaterialColors.jl) —
a pure-Julia port of Google's
[material-color-utilities](https://github.com/material-foundation/material-color-utilities).

That package is where the color space, tonal palettes, scheme generation and
contrast helpers live, and it is usable on its own:
**[MaterialColors documentation](https://mthelm85.github.io/MaterialColors.jl/dev/)**.

## What MaterialDocs uses it for

A [`ThemeConfig`](@ref) carries a seed hex color. At build time MaterialDocs
calls `hex_scheme_pair` to generate the light and dark schemes — 34 MD3 color
roles each — and writes every role out as a CSS custom property:

```css
--md-sys-color-primary
--md-sys-color-on-primary-container
--md-sys-color-surface-container-high
```

All 34 roles are emitted whether or not the bundled stylesheets use them, so
custom CSS has the complete set available. See [Theming](@ref) for choosing a
seed and [Configuration](@ref) for referencing these tokens from your own
stylesheets.

## Why the tokens are trustworthy

HCT combines CAM16 hue and chroma with CIELAB lightness, which makes **tone map
directly to contrast**. Roles are placed at the tones the MD3 specification
assigns, so pairings such as `primary` / `on_primary` meet WCAG AA by
construction rather than by hand-checking. MaterialDocs' test suite asserts this
for every role pair, in both light and dark.

If you override a role through `custom_colors`, that guarantee no longer holds
for the overridden value — check it yourself with `MaterialColors.meets_aa`.
