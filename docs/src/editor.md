```@meta
CurrentModule = MaterialDocs
```

# Theme Editor

[`editor`](@ref) rebuilds your documentation, serves it locally, and injects a
floating panel that re-themes the real pages as you adjust them. You are editing
your actual site, not a preview of swatches.

```julia
using MaterialDocs
MaterialDocs.editor()
```

That runs `docs/make.jl`, starts a server on `127.0.0.1`, and opens a browser.

## Workflow

1. Adjust the seed color, fonts, and shape in the panel. The page re-themes live.
2. Navigate around your real docs to check the theme against actual content.
3. Click **Copy TOML** to copy the theme to your clipboard.
4. Save it as `docs/.materialdocs.toml`.

That file is picked up automatically on the next build — no `make.jl` change
needed. See [Theming](@ref).

## Why it works

Every stylesheet rule references a `var(--md-sys-*)` custom property and never a
literal color. The editor sets those properties on `:root`, so one assignment
re-themes every component at once.

The panel has no color engine of its own. Each time you change a color it asks
the editor's server for a new scheme, and the server generates it with the same
code the build uses — so what you see is what your built site will get.

Your color, font, and shape choices are kept in `sessionStorage`, and the
light/dark choice in `localStorage`, so both survive navigation — even on a site
built without a navbar toggle.

## Options

```julia
MaterialDocs.editor(
    build = "docs/build",
    port = 8000,
    make = "docs/make.jl",
    theme = resolve_theme(:ocean_depth),
)
```

- **`make`** — the build script to run before serving, so you are always editing
  the current state of your sources. Pass `nothing` to skip the rebuild and serve
  whatever is already in `build`.
- **`build`** — the directory to serve.
- **`port`** — `0` (the default) picks a free port.
- **`host`** — the interface to listen on. The default, `127.0.0.1`, keeps the
  preview reachable only from your machine. Pass `Sockets.IPv4(0)` to open it to
  your network, for example to check a build on a phone; the editor logs a
  warning when you do.
- **`theme`** — the config the panel opens with.

Press `Ctrl+C` in the REPL to stop.

## Controls

| Control | Effect |
|---|---|
| **Seed** | The primary color everything else is derived from |
| **Background** / **Text** | Override surface and on-surface directly |
| **Secondary** / **Tertiary** | Override those palettes; empty means derive from the seed |
| **Fonts** | Display, body, and code families, loaded from Google Fonts on demand |
| **Corner radius** | `sharp`, `default`, `rounded`, or `pill` |
| **Light/dark** | Switch modes; the palette regenerates for the active mode |

The swatch grid previews sixteen of the generated roles. The full scheme is 34
roles — see [Color Engine](@ref).

!!! note "The editor is a development tool"
    Apart from rebuilding `docs/build` when it starts, it writes nothing to
    disk. **Copy TOML** only puts the theme on your clipboard, so closing the
    editor without saving that TOML discards your changes.
