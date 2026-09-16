```@meta
CurrentModule = MaterialDocs
```

# Configuration

Every option is a keyword to [`Material3`](@ref). It accepts **every keyword
`Documenter.HTML` does**, with the same meaning and defaults, so switching
writers is a rename — see [Documenter.HTML options](@ref).
The options below are the ones MaterialDocs adds.

```julia
format = Material3(
    theme = :ocean_depth,
    dark_mode = :toggle,
    toc_depth = 3,
    logo = "assets/logo.svg",
    favicon = "assets/favicon.ico",
)
```

## Appearance

### `theme`

A built-in theme name (`Symbol`) or a [`ThemeConfig`](@ref). Defaults to
`:default`, which first checks for `docs/.materialdocs.toml` relative to the
directory the build runs from — see [Theming](@ref).

### `dark_mode`

How light and dark are chosen. Default `:auto`.

| Value | Behavior |
|---|---|
| `:auto` | Follows the reader's `prefers-color-scheme` |
| `:light` | Always light; no dark rules are emitted at all |
| `:dark` | Always dark |
| `:toggle` | Adds a navbar toggle, remembered in `localStorage` |

### `logo` and `favicon`

Paths relative to `docs/src`, copied into the build:

```julia
Material3(logo = "assets/logo.svg", favicon = "assets/favicon.ico")
```

Neither is required. As with `Documenter.HTML`, a `docs/src/assets/logo.svg`
(or `.png`, `.webp`, `.gif`, `.jpg`, `.jpeg`) is used automatically, together
with `assets/logo-dark.*` for dark mode when present, and an `.ico` listed in
`assets` sets the favicon.

The logo appears in the navbar at 32px tall. SVG is recommended so it stays
sharp at any display density.

## Navigation

### `toc_depth`

Deepest heading level shown in the on-this-page rail. Between `2` and `4`,
default `3`.

### `repolink`

The repository link in the navbar. By default it is derived from Documenter's
configured remote.

| Value | Behavior |
|---|---|
| unset, or `:auto` | Derived from Documenter's configured remote |
| a `String` | Used as the URL verbatim |
| `nothing` | No link |

The label names the host when it is GitHub, GitLab, Bitbucket, or Azure DevOps.
GitHub and GitLab also get their own icon; every other host shows a generic git
icon.

```julia
Material3(repolink = "https://codeberg.org/you/MyPackage.jl")
```

### `versions`

Show the version selector once the site has been deployed with `deploydocs`.
Default `true`.

It reads `DOCUMENTER_CURRENT_VERSION` from `siteinfo.js` and `DOC_VERSIONS` from
`../versions.js` — both written by `deploydocs`. On a local build neither exists,
so the selector stays hidden and the two missing files are harmless.

Switching versions keeps you on the same page where that page exists in the
target version, and falls back to its home page where it does not.

### `search`

Enable the search bar and index. Default `true`.

Search is entirely client-side: a JSON index is generated at build time and
loaded on first use. Ctrl/Cmd+K opens it from anywhere.

## Documenter.HTML options

`Material3` passes these to a real `Documenter.HTML`, so names, defaults and
validation are Documenter's own — see the
[`Documenter.HTML` reference](https://documenter.juliadocs.org/stable/lib/public/#Documenter.HTML)
for full details. How MaterialDocs renders each:

| Keyword | In MaterialDocs |
|---|---|
| `prettyurls` | Directory-style URLs (`page/index.html`, linked as `./page/`). Set it to `false`, or condition it on CI, to open a build from disk — see [Getting Started](@ref) |
| `repolink` | The navbar repository link, as above |
| `canonical` | Canonical link and `og:url` tags; with `assets/preview.*`, preview-image tags |
| `description` | Description meta tags. A page's `@meta Description` overrides it |
| `lang` | The `lang` attribute of every page |
| `analytics` | Google Analytics |
| `assets` | Local CSS, JS and ICO files, remote [`asset`](https://documenter.juliadocs.org/stable/lib/public/#Documenter.asset)s and `RawHTMLHeadContent`, in order, after MaterialDocs' stylesheet |
| `footer` | Markdown in the page footer, replacing the default attribution; `nothing` removes it |
| `highlights` | Extra highlight.js languages |
| `sidebar_sitename` | `false` hides the site name in the navbar |
| `inventory_version` | The version recorded in `objects.inv` (see below) |
| `edit_link`, `edit_branch`, `disable_git` | An edit button on each page linking to its source; a page's absolute `@meta EditURL` overrides it |
| `collapselevel` | Sidebar sections at this nesting level or deeper start collapsed, except the one holding the current page |
| `mathengine` | `KaTeX` (default; its config's render options such as `macros` apply), `MathJax2` or `MathJax3` with their config and `url`, or `nothing` to leave math as TeX. Loaded only on pages with math |
| `size_threshold`, `size_threshold_warn`, `size_threshold_ignore` | Pages over `size_threshold_warn` log a warning; over `size_threshold` the build fails, except pages listed in `size_threshold_ignore` |
| `example_size_threshold` | `@example` images at least this large are written to files beside the page; larger HTML output falls back to an image when one exists |
| `search_size_threshold_warn` | Warns when the search index is larger |
| `warn_outdated` | On deployed docs that aren't the newest release (or are the development version), a banner linking to the same page in the stable docs |
| `ansicolor` | Colored `@example` and `@repl` output, using ANSI colors toned for contrast in light and dark mode. As with `Documenter.HTML`, output is only captured in color when Julia runs with color enabled |
| `prerender`, `node`, `highlightjs` | Accepted with a warning; they only affect Documenter's own theme |

### Custom CSS and JavaScript

Add them through `assets`, with paths relative to `docs/src`:

```julia
Material3(assets = ["assets/extra.css", "assets/extra.js"])
```

Because all styling is driven by `--md-sys-*` custom properties, custom CSS
should reference those tokens rather than literal colors. That way it keeps
working in both light and dark mode:

```css
.my-callout {
  background: var(--md-sys-color-surface-container);
  color: var(--md-sys-color-on-surface);
  border-radius: var(--md-sys-shape-corner-medium);
}
```

### Cross-project links

Every build writes `objects.inv`, the same cross-reference inventory
`Documenter.HTML` writes, so packages using
[DocumenterInterLinks](https://github.com/JuliaDocs/DocumenterInterLinks.jl) can
link into your documentation. `inventory_version` sets the version recorded in
it; by default it is read from the `Project.toml` one level above the docs root.
