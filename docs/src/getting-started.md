```@meta
CurrentModule = MaterialDocs
```

# Getting Started

## Add MaterialDocs to your docs environment

MaterialDocs belongs in `docs/Project.toml`, alongside Documenter — not in your
package's own dependencies. It is only needed when building documentation.

```julia
using Pkg
Pkg.activate("docs")
Pkg.add("MaterialDocs")
```

Your `docs/Project.toml` should end up looking like this:

```toml
[deps]
Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
MaterialDocs = "10bdffc8-969c-4dd4-83f3-742518eccd6b"
MyPackage = "..."

[sources]
MyPackage = {path = ".."}

[compat]
Documenter = "1"
```

## Switch the format

In `docs/make.jl`, swap `Documenter.HTML` for [`Material3`](@ref):

```julia
using Documenter, MaterialDocs, MyPackage

makedocs(
    sitename = "MyPackage.jl",
    modules  = [MyPackage],
    format   = Material3(),
    pages = [
        "Home" => "index.md",
        "API"  => "api.md",
    ],
)

deploydocs(repo = "github.com/you/MyPackage.jl")
```

Build it:

```julia
julia --project=docs docs/make.jl
```

The result lands in `docs/build`. Open `docs/build/index.html` directly, or use
the [Theme Editor](@ref), which rebuilds and serves it for you.

!!! tip "Opening a build from disk"
    `prettyurls = true` (the default) produces directory-style URLs like
    `./guide/`, which browsers cannot follow from the filesystem. A common
    pattern is to enable them only on CI:

    ```julia
    format = Material3(prettyurls = get(ENV, "CI", nothing) == "true")
    ```

## Pick a theme

Twelve themes ship built in. Pass one by name:

```julia
format = Material3(theme = :ocean_depth)
```

See [Theming](@ref) for the full list, and for building your own from a seed color.

## Add a dark mode toggle

By default the site follows the reader's system preference. To offer an explicit
toggle in the navbar:

```julia
format = Material3(dark_mode = :toggle)
```

## Deploying

MaterialDocs does not change how deployment works — keep using `deploydocs`:

```julia
deploydocs(
    repo = "github.com/you/MyPackage.jl",
    devbranch = "main",
)
```

Once `deploydocs` has published more than one version, the navbar version
selector appears automatically. It reads the `versions.js` and `siteinfo.js`
files that `deploydocs` writes, so there is nothing extra to configure. On local
builds those files do not exist and the selector stays hidden.

!!! note "`devbranch` must match your default branch"
    The PkgTemplates default is `master`. If your repository uses `main`,
    set `devbranch = "main"` or deployment will silently never happen.
