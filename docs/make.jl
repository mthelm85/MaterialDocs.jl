using MaterialDocs
using Documenter

DocMeta.setdocmeta!(MaterialDocs, :DocTestSetup, :(using MaterialDocs); recursive=true)

makedocs(;
    modules=[MaterialDocs],
    authors="mthelm85",
    sitename="MaterialDocs.jl",
    format=Documenter.HTML(;
        canonical="https://mthelm85.github.io/MaterialDocs.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mthelm85/MaterialDocs.jl",
    devbranch="master",
)
