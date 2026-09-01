```@meta
CurrentModule = MaterialDocs
```

# Configuration

Every option is a keyword to [`Material3`](@ref).

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
`:default`, which first checks for `docs/.materialdocs.toml` — see [Theming](@ref).

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

The logo appears in the navbar at 32px tall. SVG is recommended so it stays
sharp in both themes.

### `footer`

Extra HTML placed above the generated attribution line:

```julia
Material3(footer = "Made with ❤️ and Julia")
```

## Navigation

### `toc_depth`

Deepest heading level shown in the on-this-page rail. Between `2` and `4`,
default `3`.

### `sidebar_collapsed`

Start sidebar sections collapsed. Default `false`. Reader changes persist in
`localStorage` either way.

### `repolink`

The repository link in the navbar. Default `:auto`.

| Value | Behavior |
|---|---|
| `:auto` | Derived from Documenter's configured remote |
| a `String` | Used as the URL verbatim |
| `nothing` | No link |

The icon and label follow the host — GitHub, GitLab, Bitbucket, and Azure DevOps
are recognised, with a generic git icon otherwise.

```julia
Material3(repolink = "https://codeberg.org/you/MyPackage.jl")
```

### `versions`

Show the version selector when the site has been deployed with more than one
version. Default `true`.

It reads `DOCUMENTER_CURRENT_VERSION` from `siteinfo.js` and `DOC_VERSIONS` from
`../versions.js` — both written by `deploydocs`. On a local build neither exists,
so the selector stays hidden and the two missing files are harmless.

Switching versions keeps you on the same page where that page exists in the
target version, and falls back to its home page where it does not.

### `search`

Enable the search bar and index. Default `true`.

Search is entirely client-side: a JSON index is generated at build time and
loaded on first use. Ctrl/Cmd+K opens it from anywhere.

## Output

### `prettyurls`

Directory-style URLs (`page/index.html`, linked as `./page/`). Default `true`.

Set it to `false`, or condition it on CI, when the build needs to be opened from
disk — see [Getting Started](@ref).

### `custom_css` and `custom_js`

Extra files, relative to `docs/src`, copied in and linked after the generated
assets:

```julia
Material3(
    custom_css = ["assets/extra.css"],
    custom_js  = ["assets/extra.js"],
)
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

### `analytics`

A Google Analytics measurement ID:

```julia
Material3(analytics = "G-XXXXXXXXXX")
```
