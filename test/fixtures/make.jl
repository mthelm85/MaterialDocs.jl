# Test fixture — builds docs with MaterialDocs writer
using Documenter
using MaterialDocs

makedocs(;
    sitename = "TestPackage.jl",
    format = Material3(theme = :ocean_depth, dark_mode = :toggle, toc_depth = 3),
    modules = [MaterialDocs],
    pages = [
        "Home" => "index.md",
        "API" => "api.md",
    ],
    root = @__DIR__,
    source = "src",
    build = "build",
    warnonly = true,
)
