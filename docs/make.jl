using MaterialDocs
using Documenter

DocMeta.setdocmeta!(MaterialDocs, :DocTestSetup, :(using MaterialDocs); recursive=true)

makedocs(;
    modules = [MaterialDocs],
    authors = "mthelm85",
    sitename = "MaterialDocs.jl",
    # MaterialDocs builds its own documentation — this site is the demo.
    format = Material3(
        theme = :ocean_depth,
        dark_mode = :toggle,
    ),
    # Internal helpers are deliberately undocumented in the manual
    checkdocs = :exports,
    pages = [
        "Home"            => "index.md",
        "Getting Started" => "getting-started.md",
        "Theming"         => "theming.md",
        "Configuration"   => "configuration.md",
        "Theme Editor"    => "editor.md",
        "Color Engine"    => "colors.md",
        "API Reference"   => "api.md",
    ],
)

deploydocs(;
    repo = "github.com/mthelm85/MaterialDocs.jl",
    devbranch = "main",
)
