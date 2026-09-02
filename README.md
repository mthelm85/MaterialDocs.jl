# MaterialDocs.jl

**A [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) writer that generates [Material Design 3](https://m3.material.io) documentation sites.**

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mthelm85.github.io/MaterialDocs.jl/dev/)
[![Build Status](https://github.com/mthelm85/MaterialDocs.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mthelm85/MaterialDocs.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Pass `Material3()` as your format and every page is rendered against a full MD3
token system — colors, typography, shape, elevation, and motion — generated at
build time from a single seed color.

No Node.js, no build step, no external toolchain. Pure Julia, and the output is
a self-contained static site.

**[MaterialDocs' own documentation](https://mthelm85.github.io/MaterialDocs.jl/dev/) is built with MaterialDocs** — the site is the demo.

## Installation

Not yet registered in the General registry. Add it by URL:

```julia
using Pkg
Pkg.activate("docs")
Pkg.add(url = "https://github.com/mthelm85/MaterialDocs.jl.git")
```

MaterialDocs belongs in `docs/Project.toml` alongside Documenter — it is only
needed when building documentation, never at runtime.

## Quick start

In `docs/make.jl`, replace `Documenter.HTML` with `Material3`:

```julia
using Documenter, MaterialDocs, MyPackage

makedocs(
    sitename = "MyPackage.jl",
    modules  = [MyPackage],
    format   = Material3(theme = :ocean_depth, dark_mode = :toggle),
    pages    = ["Home" => "index.md"],
)

deploydocs(repo = "github.com/you/MyPackage.jl", devbranch = "main")
```

That is the whole integration. MaterialDocs registers itself through
Documenter's `FormatSelector`, so `makedocs` dispatches to it automatically.

Only the rendering stage is replaced — parsing, cross-references, doctests, and
`@docs` blocks are unchanged Documenter, so existing documentation works
without edits.

## Features

- **Perceptually uniform color.** A pure-Julia port of Google's
  [material-color-utilities](https://github.com/material-foundation/material-color-utilities):
  CAM16, HCT, and tonal palettes. One seed hex generates 34 MD3 color roles in
  light and dark, placed at tones chosen to meet WCAG AA.
- **Twelve built-in themes**, or your own from a seed color and three fonts.
- **A live theme editor.** `MaterialDocs.editor()` rebuilds your docs, serves
  them, and injects a panel that re-themes the real pages as you drag a color
  picker — then exports a config file.
- **Light and dark modes**, following the system preference or an explicit toggle.
- **MD3 search.** A search bar that expands into a docked search view on wide
  windows and a full-screen view on narrow ones. Entirely client-side.
- **Version selector and repository link**, wired to the metadata `deploydocs`
  already writes. No extra configuration.
- **Responsive**, with a slide-in navigation drawer on small screens.

## Theming

Pick a built-in theme:

```julia
format = Material3(theme = :forest)
```

`:default`, `:ocean_depth`, `:solar_flare`, `:midnight`, `:forest`, `:arctic`,
`:rose_garden`, `:amber_workshop`, `:lavender`, `:sandstone`, `:neon_lab`, `:slate`

Or build your own — everything is derived from the seed:

```julia
format = Material3(theme = ThemeConfig(
    seed = "#2E7D32",
    display_font = "Literata",
    body_font = "Source Serif 4",
    code_font = "JetBrains Mono",
    corner_radius = :rounded,
))
```

A theme can also live in `docs/.materialdocs.toml`, which is picked up
automatically — no `make.jl` change needed. That is the format the theme editor
exports, so the usual workflow is to design a theme visually and save the file.

## Theme editor

```julia
using MaterialDocs
MaterialDocs.editor()
```

Rebuilds your documentation, serves it locally, and injects a floating panel.
Adjust the seed color, fonts, and shape and the real pages re-theme instantly —
because every rule references a `var(--md-sys-*)` custom property and never a
literal color. Click **Copy TOML** and save the result as
`docs/.materialdocs.toml`.

## Documentation

Full manual at **[mthelm85.github.io/MaterialDocs.jl/dev](https://mthelm85.github.io/MaterialDocs.jl/dev/)** —
getting started, every `Material3` option, theming, the editor, and the color
engine API.

## Acknowledgements

The color engine is a port of Google's
[material-color-utilities](https://github.com/material-foundation/material-color-utilities)
(Apache 2.0). See [LICENSES_THIRD_PARTY.md](LICENSES_THIRD_PARTY.md).

Material Design is a trademark of Google. This project is not affiliated with
or endorsed by Google.

## License

MIT — see [LICENSE](LICENSE).
