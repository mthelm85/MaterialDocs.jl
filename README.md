# MaterialDocs.jl

**A [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) writer that generates [Material Design 3](https://m3.material.io) documentation sites.**

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mthelm85.github.io/MaterialDocs.jl/dev/)
[![Build Status](https://github.com/mthelm85/MaterialDocs.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mthelm85/MaterialDocs.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Pass `Material3()` as your format and every page is rendered against a full MD3
token system — colors, typography, shape, elevation, and motion — generated at
build time from a single seed color.

Pure Julia, with no Node.js or JavaScript toolchain. The output is a static site
you can host anywhere. Pages load their fonts from Google Fonts, and syntax
highlighting and math typesetting from a CDN, so readers without network access
see system fonts, unhighlighted code, and raw LaTeX.

**[MaterialDocs' own documentation](https://mthelm85.github.io/MaterialDocs.jl/dev/) is built with MaterialDocs** — the site is the demo.

## Installation

```julia
using Pkg
Pkg.activate("docs")
Pkg.add("MaterialDocs")
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

- **A full palette from one color.**
  [MaterialDesignColors.jl](https://github.com/mthelm85/MaterialDesignColors.jl)
  turns a single seed into all 34 MD3 color roles, in light and dark. Every
  text-on-container pairing in the twelve built-in themes clears WCAG AA
  contrast.
- **Twelve built-in themes**, or your own from a seed color and three fonts.
- **A live theme editor.** `MaterialDocs.editor()` rebuilds your docs, serves
  them locally, and injects a panel that re-themes the real pages as you drag a
  color picker — then gives you the theme as TOML to save.
- **Light and dark modes**, following the system preference or an explicit toggle.
- **Everything Documenter renders.** Docstrings, doctests, `@example` output
  (HTML, SVG, PNG, JPEG, GIF, WebP, LaTeX, Markdown), and math via KaTeX.
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
produces, so the usual workflow is to design a theme visually and save the file.

## Theme editor

```julia
using MaterialDocs
MaterialDocs.editor()
```

Rebuilds your documentation, serves it on `127.0.0.1`, and injects a floating
panel. Adjust the seed color, fonts, and shape and the real pages re-theme
instantly — because every rule references a `var(--md-sys-*)` custom property
and never a literal color. Click **Copy TOML** and save the result as
`docs/.materialdocs.toml`.

## Documentation

Full manual at **[mthelm85.github.io/MaterialDocs.jl/dev](https://mthelm85.github.io/MaterialDocs.jl/dev/)** —
getting started, every `Material3` option, theming, the editor, and how colors
are generated.

## Acknowledgements

Color generation comes from
[MaterialDesignColors.jl](https://github.com/mthelm85/MaterialDesignColors.jl),
a port of Google's
[material-color-utilities](https://github.com/material-foundation/material-color-utilities)
(Apache 2.0). MaterialDocs itself contains no third-party code; see
[LICENSES_THIRD_PARTY.md](LICENSES_THIRD_PARTY.md).

Material Design is a trademark of Google. This project is not affiliated with
or endorsed by Google.

## License

MIT — see [LICENSE](LICENSE).
