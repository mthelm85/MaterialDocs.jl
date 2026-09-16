```@meta
CurrentModule = MaterialDocs
```

# Color Engine

Every color on a MaterialDocs site is generated at build time from a single
seed, using [MaterialDesignColors.jl](https://github.com/mthelm85/MaterialDesignColors.jl) —
a pure-Julia port of Google's
[material-color-utilities](https://github.com/material-foundation/material-color-utilities).

That package is where the color space, tonal palettes, scheme generation and
contrast helpers live, and it is usable on its own:
**[MaterialDesignColors documentation](https://mthelm85.github.io/MaterialDesignColors.jl/dev/)**.

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

## Contrast

HCT combines CAM16 hue and chroma with CIELAB lightness, which makes **tone map
directly to contrast**. Each role sits at the tone the MD3 specification assigns
it, so text roles land far enough from their containers to stay readable.

For the twelve built-in themes this holds in practice: every text-on-container
pairing — `on_primary` on `primary`, `on_surface` on `surface`, and so on —
clears WCAG AA (4.5:1) in both light and dark, and the lowest is 6.4:1.

If you use your own seed, or override a role through `custom_colors`, check the
pairings you rely on with `MaterialDesignColors.meets_aa`.
