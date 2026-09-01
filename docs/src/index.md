```@meta
CurrentModule = MaterialDocs
```

# MaterialDocs.jl

A [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) writer that generates
[Material Design 3](https://m3.material.io) documentation sites.

Pass `Material3()` as your format and every page is rendered against a full MD3
token system — colors, typography, shape, elevation, and motion — generated at
build time from a single seed color.

**This site is built with MaterialDocs.** Everything you see here is the output.

## Installation

```julia
using Pkg
Pkg.add("MaterialDocs")
```

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
```

That is the whole integration. MaterialDocs registers itself through Documenter's
`FormatSelector`, so `makedocs` dispatches to it automatically.

## What you get

- **Perceptually uniform color.** A port of Google's
  [material-color-utilities](https://github.com/material-foundation/material-color-utilities)
  to pure Julia. One seed hex generates 34 MD3 color roles with guaranteed
  contrast ratios. See [Color Engine](@ref).
- **Twelve built-in themes**, or your own via [`ThemeConfig`](@ref). See [Theming](@ref).
- **A live theme editor.** [`editor`](@ref) serves your real documentation with a
  panel that re-themes it as you drag a color picker, then exports a config file.
  See [Theme Editor](@ref).
- **Light and dark modes**, following the system preference or a toggle.
- **MD3 search.** A search bar that expands into a docked search view on wide
  windows and a full-screen view on narrow ones.
- **Version selector and repository link** in the navbar, wired to the metadata
  `deploydocs` already writes.
- **No Node.js.** Pure Julia, and the output is a self-contained static site.

## How it fits together

MaterialDocs replaces only Documenter's rendering stage. Everything upstream —
parsing, cross-references, doctests, `@docs` blocks — is unchanged Documenter,
so existing documentation works without edits.

Because every stylesheet references `var(--md-sys-*)` custom properties and never
a literal color, changing the tokens re-themes the entire site. That is what makes
the live editor possible.

## Where to go next

- [Getting Started](@ref) — build your first site
- [Theming](@ref) — pick or design a theme
- [Configuration](@ref) — every `Material3` option
- [API Reference](@ref) — full docstrings
