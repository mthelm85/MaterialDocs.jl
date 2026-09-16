using MaterialDocs
using MaterialDesignColors
using Documenter
using Test
using Sockets
using Aqua
using JET
using CodecZlib

struct UnknownFixtureElement <: Documenter.MarkdownAST.AbstractInline end
Documenter.MarkdownAST.iscontainer(::UnknownFixtureElement) = true

@testset "MaterialDocs.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(MaterialDocs)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(MaterialDocs; target_modules = (MaterialDocs,))
    end

    # ─────────────────────────────────────────────────────────────────
    # Phase 1: HCT Color Engine
    # ─────────────────────────────────────────────────────────────────


    # ─────────────────────────────────────────────────────────────────
    # Phase 2: Theme System & Writer Skeleton
    # ─────────────────────────────────────────────────────────────────

    @testset "ThemeConfig defaults" begin
        tc = ThemeConfig()
        @test tc.name == "custom"
        @test tc.seed == "#6750A4"
        @test tc.secondary_seed === nothing
        @test tc.tertiary_seed === nothing
        @test tc.display_font == "Roboto"
        @test tc.body_font == "Roboto"
        @test tc.code_font == "Roboto Mono"
        @test tc.corner_radius == :default
        @test isempty(tc.custom_colors)
    end

    @testset "ThemeConfig custom" begin
        tc = ThemeConfig(
            name="Test",
            seed="#2E7D32",
            secondary_seed="#006B5E",
            tertiary_seed="#E65100",
            display_font="Literata",
            body_font="Source Serif 4",
            code_font="Fira Code",
            corner_radius=:default,
            custom_colors=Dict("primary" => "#112233"),
        )
        @test tc.name == "Test"
        @test tc.seed == "#2E7D32"
        @test tc.secondary_seed == "#006B5E"
        @test tc.tertiary_seed == "#E65100"
        @test tc.display_font == "Literata"
        @test tc.corner_radius == :default
        @test tc.custom_colors["primary"] == "#112233"
    end

    @testset "ThemeConfig validation" begin
        @test_throws ArgumentError ThemeConfig(corner_radius=:bad)
    end

    @testset "ThemeConfig show" begin
        tc = ThemeConfig(name="Test", seed="#123456")
        s = sprint(show, tc)
        @test contains(s, "ThemeConfig")
        @test contains(s, "Test")
        @test contains(s, "#123456")
    end

    @testset "Corner radius presets" begin
        @test haskey(MaterialDocs.CORNER_RADII, :sharp)
        @test haskey(MaterialDocs.CORNER_RADII, :default)
        @test haskey(MaterialDocs.CORNER_RADII, :rounded)
        @test haskey(MaterialDocs.CORNER_RADII, :pill)
        # Sharp starts with zero
        @test MaterialDocs.CORNER_RADII[:sharp][1] == 0
        # Rounded should be increasing
        r = collect(MaterialDocs.CORNER_RADII[:rounded])
        @test issorted(r)
    end

    @testset "Built-in themes" begin
        @test length(BUILTIN_THEMES) == 12
        expected = [:default, :ocean_depth, :solar_flare, :midnight, :forest,
                    :arctic, :rose_garden, :amber_workshop, :lavender,
                    :sandstone, :neon_lab, :slate]
        for name in expected
            @test haskey(BUILTIN_THEMES, name)
            tc = BUILTIN_THEMES[name]
            @test tc isa ThemeConfig
            @test startswith(tc.seed, "#")
            @test length(tc.seed) == 7
            @test !isempty(tc.display_font)
        end
    end

    @testset "resolve_theme" begin
        # Symbol → ThemeConfig
        tc = resolve_theme(:default)
        @test tc === BUILTIN_THEMES[:default]
        @test tc.name == "Default"

        # ThemeConfig passthrough
        custom = ThemeConfig(seed="#FF0000")
        @test resolve_theme(custom) === custom

        # Unknown symbol
        @test_throws ArgumentError resolve_theme(:nonexistent)
    end

    @testset "Material3 defaults" begin
        m3 = Material3()
        @test m3.theme === BUILTIN_THEMES[:default]
        @test m3.dark_mode == :auto
        @test m3.toc_depth == 3
        @test m3.search == true
        @test !(m3.html.repolink isa Union{String,Nothing})  # unset: derived from the remote
        @test Material3(repolink = :auto).html.repolink == m3.html.repolink
        @test m3.versions == true
        @test m3.logo === nothing
        @test m3.favicon === nothing
        @test m3.html.prettyurls == true
        @test isempty(m3.html.assets)
    end

    # REQ: The Material3 constructor shall not accept `sidebar_collapsed`
    # (Documenter's `collapselevel` replaces it) or `custom_css`/`custom_js`
    # (Documenter's `assets` replaces them).
    @testset "Material3 rejects removed options" begin
        @test !hasfield(Material3, :sidebar_collapsed)
        @test_throws MethodError Material3(sidebar_collapsed = true)
        @test_throws MethodError Material3(custom_css = ["a.css"])
        @test_throws MethodError Material3(custom_js = ["a.js"])
    end

    @testset "Material3 with symbol theme" begin
        m3 = Material3(theme=:ocean_depth, dark_mode=:toggle, toc_depth=4)
        @test m3.theme.name == "Ocean Depth"
        @test m3.dark_mode == :toggle
        @test m3.toc_depth == 4
    end

    @testset "Material3 with ThemeConfig" begin
        tc = ThemeConfig(seed="#E65100", name="Custom Orange")
        m3 = Material3(theme=tc, dark_mode=:light)
        @test m3.theme === tc
        @test m3.dark_mode == :light
    end

    @testset "Material3 validation" begin
        @test_throws ArgumentError Material3(dark_mode=:bad)
        @test_throws ArgumentError Material3(toc_depth=1)
        @test_throws ArgumentError Material3(toc_depth=5)
    end

    @testset "Material3 show" begin
        m3 = Material3(theme=:midnight, dark_mode=:toggle)
        s = sprint(show, m3)
        @test contains(s, "Material3")
        @test contains(s, "Midnight")
        @test contains(s, "toggle")
    end

    @testset "CSS generation" begin
        m3 = Material3(theme=:ocean_depth, dark_mode=:toggle)
        theme = m3.theme
        light, dark = hex_scheme_pair(theme.seed;
            secondary=theme.secondary_seed, tertiary=theme.tertiary_seed)
        css = MaterialDocs.build_css(theme, light, dark, m3)

        # Should contain all token categories
        @test contains(css, ":root {")
        @test contains(css, "--md-sys-color-primary:")
        @test contains(css, "--md-sys-color-on-primary:")
        @test contains(css, "--md-sys-color-surface:")
        @test contains(css, "--md-sys-typescale-display-large-font:")
        @test contains(css, "--md-sys-typescale-body-large-size:")
        @test contains(css, "--md-sys-shape-corner-medium:")
        @test contains(css, "--md-sys-elevation-1:")
        @test contains(css, "--md-sys-motion-easing-standard:")

        # Dark mode blocks
        @test contains(css, "@media (prefers-color-scheme: dark)")
        @test contains(css, "[data-theme=\"dark\"]")
        @test contains(css, ":root:not([data-theme=\"light\"])")

        # Layout (from base.css)
        @test contains(css, ".md-layout")
        @test contains(css, ".md-sidebar")
        @test contains(css, ".md-content")
        @test contains(css, ".md-navbar")

        # Components use tokens, not literal colors (Phase 5)
        @test contains(css, "var(--md-sys-color-primary-container)")
        @test contains(css, "var(--md-sys-color-on-primary-container)")
        @test contains(css, "var(--md-sys-color-secondary-container)")
        @test contains(css, "var(--md-sys-color-error-container)")
        @test contains(css, "var(--md-sys-color-surface-container)")
        @test contains(css, "var(--md-sys-shape-corner-medium)")
        @test contains(css, "var(--md-sys-motion-easing-standard)")

        # Static CSS file sections present
        @test contains(css, "base.css")
        @test contains(css, "components.css")
        @test contains(css, "nav.css")
        @test contains(css, "print.css")

        # Component classes from static CSS
        @test contains(css, ".md-code-block")
        @test contains(css, ".md-code-inline")
        @test contains(css, ".md-blockquote")
        @test contains(css, ".md-admonition")
        @test contains(css, ".md-admonition-note")
        @test contains(css, ".md-admonition-warning")
        @test contains(css, ".md-admonition-tip")
        @test contains(css, ".md-admonition-danger")
        @test contains(css, ".md-docstring")
        @test contains(css, ".md-docstring-binding")
        @test contains(css, ".md-table-wrap")
        @test contains(css, ".md-copy-btn")
        @test contains(css, ".md-footnote")
        @test contains(css, ".md-math-display")
        @test contains(css, ".md-figure")
        @test contains(css, ".md-toc-link")
        @test contains(css, ".md-footer")
        @test contains(css, ".md-heading-anchor")

        # Print styles
        @test contains(css, "@media print")

        # Responsive breakpoints
        @test contains(css, "@media (max-width:")

        # MD3 search bar + search view CSS
        @test contains(css, ".md-search-bar")
        @test contains(css, ".md-search-view")
        @test contains(css, ".md-search-input")
        @test contains(css, ".md-search-item")
        @test contains(css, ".md-search-selected")
        # Version selector + repo link
        @test contains(css, ".md-version-menu")
        @test contains(css, ".md-repo-link")

        # MD3 state layers and focus indicator
        @test contains(css, "--md-sys-state-hover-opacity: 0.08")
        @test contains(css, "--md-sys-state-focus-opacity: 0.10")
        @test contains(css, "--md-sys-state-pressed-opacity: 0.10")
        @test contains(css, "var(--md-sys-state-hover-opacity)")
        @test contains(css, "outline: 3px solid var(--md-sys-color-secondary)")
        # MD3 body-large tracking is 0.5px at 16px
        @test contains(css, "--md-sys-typescale-body-large-tracking: 0.03125em")
        # Touch targets expand on coarse pointers
        @test contains(css, "@media (pointer: coarse)")

        # Sidebar collapse/mobile CSS (Phase 6)
        @test contains(css, ".md-nav-collapsed")
        @test contains(css, ".md-hamburger")
        @test contains(css, ".md-sidebar-open")
    end

    @testset "CSS dark mode variants" begin
        # :light mode should NOT have any dark blocks
        m3_light = Material3(dark_mode=:light)
        theme = m3_light.theme
        light, dark = hex_scheme_pair(theme.seed)
        css_light = MaterialDocs.build_css(theme, light, dark, m3_light)
        @test !contains(css_light, "@media (prefers-color-scheme: dark)")
        @test !contains(css_light, "[data-theme=\"dark\"]")

        # :dark mode has explicit dark toggle block but no media query
        m3_dark = Material3(dark_mode=:dark)
        css_dark = MaterialDocs.build_css(m3_dark.theme, light, dark, m3_dark)
        @test !contains(css_dark, "@media (prefers-color-scheme: dark)")
        @test contains(css_dark, "[data-theme=\"dark\"]")
    end

    @testset "CSS font stacks" begin
        # Serif font detection
        serif_stack = MaterialDocs._css_font_stack("Literata", :display)
        @test contains(serif_stack, "serif")
        @test contains(serif_stack, "'Literata'")

        # Sans font
        sans_stack = MaterialDocs._css_font_stack("Inter", :display)
        @test contains(sans_stack, "sans-serif")

        # Code font
        code_stack = MaterialDocs._css_font_stack("JetBrains Mono", :code)
        @test contains(code_stack, "monospace")
        @test contains(code_stack, "'JetBrains Mono'")
    end

    @testset "JS generation" begin
        # Toggle mode includes theme switch code
        m3_toggle = Material3(dark_mode=:toggle)
        js_toggle = MaterialDocs.build_js(m3_toggle)
        @test contains(js_toggle, "md-theme-toggle")
        @test contains(js_toggle, "localStorage")
        @test contains(js_toggle, "data-theme")

        # Auto mode has no toggle
        m3_auto = Material3(dark_mode=:auto)
        js_auto = MaterialDocs.build_js(m3_auto)
        @test !contains(js_auto, "md-theme-toggle")

        # All modes include sidebar, copy, toc modules (Phase 6)
        for js in (js_toggle, js_auto)
            @test contains(js, "sidebar.js")
            @test contains(js, "copy.js")
            @test contains(js, "toc.js")
            @test contains(js, "md-nav-section-title")   # sidebar collapse
            @test contains(js, "md-copy-btn")             # copy button
            @test contains(js, "md-toc-link")             # TOC scroll spy
            @test contains(js, "scrollIntoView")          # smooth scroll
            @test contains(js, "requestAnimationFrame")   # throttled scroll
            @test contains(js, "clipboard")               # clipboard API
        end

        # Search module — only when search=true (default)
        m3_search = Material3(dark_mode=:auto, search=true)
        js_search = MaterialDocs.build_js(m3_search)
        @test contains(js_search, "search.js")
        @test contains(js_search, "md-search-view")
        @test contains(js_search, "search-index.json")
        @test contains(js_search, "metaKey")  # Cmd/Ctrl+K shortcut

        # Search disabled
        m3_nosearch = Material3(dark_mode=:auto, search=false)
        js_nosearch = MaterialDocs.build_js(m3_nosearch)
        @test !contains(js_nosearch, "search.js")
        @test !contains(js_nosearch, "md-search-view")

        # Version selector module — only when versions=true (default)
        js_versions = MaterialDocs.build_js(Material3(dark_mode=:auto, versions=true))
        @test contains(js_versions, "versions.js")
        @test contains(js_versions, "DOC_VERSIONS")
        @test contains(js_versions, "DOCUMENTER_CURRENT_VERSION")

        js_noversions = MaterialDocs.build_js(Material3(dark_mode=:auto, versions=false))
        @test !contains(js_noversions, "versions.js")
        @test !contains(js_noversions, "DOC_VERSIONS")
    end

    @testset "NavItem and NavContext" begin
        # Basic construction
        leaf = MaterialDocs.NavItem("Home", "index.html", MaterialDocs.NavItem[], true)
        @test leaf.title == "Home"
        @test leaf.path == "index.html"
        @test isempty(leaf.children)
        @test leaf.visible

        # Section with children
        child1 = MaterialDocs.NavItem("Guide", "guide.html", MaterialDocs.NavItem[], true)
        child2 = MaterialDocs.NavItem("API", "api.html", MaterialDocs.NavItem[], true)
        section = MaterialDocs.NavItem("Manual", nothing, [child1, child2], true)
        @test section.path === nothing
        @test length(section.children) == 2

        # NavContext
        ctx = MaterialDocs.NavContext([leaf, section])
        @test length(ctx.items) == 2
    end

    @testset "Utility: _html_escape" begin
        @test MaterialDocs._html_escape("a < b & c > d") == "a &lt; b &amp; c &gt; d"
        @test MaterialDocs._html_escape("\"hello\"") == "&quot;hello&quot;"
        @test MaterialDocs._html_escape("it's") == "it&#39;s"
        @test MaterialDocs._html_escape("normal text") == "normal text"
    end

    @testset "Utility: _slugify" begin
        @test MaterialDocs._slugify("Hello World") == "hello-world"
        @test MaterialDocs._slugify("API Reference!") == "api-reference"
        @test MaterialDocs._slugify("  spaced  out  ") == "spaced-out"
        @test MaterialDocs._slugify("Under_scores") == "under-scores"
    end

    @testset "Utility: _relative_root" begin
        @test MaterialDocs._relative_root("index.html") == "./"
        @test MaterialDocs._relative_root("guide/page.html") == "../"
        @test MaterialDocs._relative_root("a/b/c.html") == "../../"
    end

    @testset "Utility: _google_fonts_link" begin
        tc = ThemeConfig(display_font="Inter", body_font="Roboto", code_font="JetBrains Mono")
        link = MaterialDocs._google_fonts_link(tc)
        @test contains(link, "fonts.googleapis.com")
        @test contains(link, "Inter")
        @test contains(link, "Roboto")
        @test contains(link, "JetBrains+Mono")
        @test contains(link, "display=swap")

        # Same display and body font should not duplicate
        tc2 = ThemeConfig(display_font="Inter", body_font="Inter")
        link2 = MaterialDocs._google_fonts_link(tc2)
        # Count "family=Inter" occurrences
        @test count("family=Inter", link2) == 1
    end

    # ─────────────────────────────────────────────────────────────────
    # Phase 3: AST → HTML Rendering (domify)
    # ─────────────────────────────────────────────────────────────────

    @testset "Integration: makedocs builds successfully" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        build_dir = joinpath(fixtures_dir, "build")

        # Clean previous build
        isdir(build_dir) && rm(build_dir; recursive=true)

        # Run makedocs inline (avoids include/module scoping issues)
        makedocs(;
            sitename = "TestPackage.jl",
            format = Material3(theme = :ocean_depth, dark_mode = :toggle, toc_depth = 3,
                               inventory_version = "1.2.3"),
            modules = [MaterialDocs],
            pages = [
                "Home" => "index.md",
                "API" => "api.md",
                "Outputs" => "outputs.md",
            ],
            root = fixtures_dir,
            source = "src",
            build = "build",
            warnonly = true,
        )

        # Output files exist
        @test isfile(joinpath(build_dir, "index.html"))
        @test isfile(joinpath(build_dir, "api", "index.html"))
        @test isfile(joinpath(build_dir, "assets", "materialdocs.css"))
        @test isfile(joinpath(build_dir, "assets", "materialdocs.js"))
    end

    # ── Documenter.HTML keyword parity ─────────────────────────────────
    #
    # REQ-P1 (Must): The Material3 constructor shall accept every keyword that
    #   Documenter.HTML accepts, with the same defaults and validation.
    # REQ-P2 (Must): When `lang` is set, each page's <html> element shall carry it.
    # REQ-P3 (Must): Each page shall carry description meta tags, taken from the
    #   page's `@meta Description` if present, else `description`, else
    #   "Documentation for <sitename>.".
    # REQ-P4 (Must): Where `canonical` is set, each page shall link its canonical
    #   URL, and where `assets/preview.*` exists, shall carry preview-image tags.
    # REQ-P5 (Must): Where `analytics` is set, each page shall load Google Analytics.
    # REQ-P6 (Must): Each page shall include `assets` in order: local CSS/JS/ICO
    #   relative to the site root, remote `asset(...)` URLs verbatim, and
    #   RawHTMLHeadContent verbatim.
    # REQ-P7 (Must): The footer shall render `footer` as Markdown, replacing the
    #   default attribution; `footer = nothing` shall omit it.
    # REQ-P8 (Must): Where no `logo` is given and `assets/logo.*` exists, the
    #   navbar shall show it, using `assets/logo-dark.*` in dark mode if present.
    # REQ-S5 (Should): Each page shall load highlight.js grammars for `highlights`.
    # REQ-S6 (Should): Where `sidebar_sitename = false`, the navbar shall omit the
    #   site name.

    @testset "Material3 accepts Documenter.HTML keywords" begin
        m3 = Material3(canonical = "https://example.org/pkg", analytics = "G-TEST",
                       collapselevel = 1, lang = "de", edit_link = nothing,
                       size_threshold = nothing, highlights = ["yaml"],
                       mathengine = Documenter.MathJax3())
        @test m3.html isa Documenter.HTML
        @test m3.html.canonical == "https://example.org/pkg"
        @test m3.html.analytics == "G-TEST"
        @test m3.html.collapselevel == 1
        @test m3.html.lang == "de"
        @test m3.html.mathengine isa Documenter.MathJax3
        # Documenter's own validation applies
        @test_throws ArgumentError Material3(collapselevel = 0)
        # Keywords neither writer knows are still rejected
        @test_throws MethodError Material3(not_a_keyword = 1)
        # Every keyword Documenter.HTML declares is accepted. A keyword added in a
        # future Documenter release fails the coverage check until sampled here.
        samples = Dict{Symbol,Any}(
            :prettyurls => false, :disable_git => true, :repolink => "https://example.org/r",
            :edit_link => nothing, :edit_branch => "main", :canonical => "https://example.org",
            :assets => String[], :analytics => "G-X", :collapselevel => 1,
            :sidebar_sitename => false, :highlights => ["yaml"],
            :mathengine => Documenter.KaTeX(), :description => "d", :footer => "f",
            :ansicolor => false, :lang => "de", :warn_outdated => false,
            :prerender => false, :node => nothing, :highlightjs => nothing,
            :size_threshold => nothing, :size_threshold_warn => nothing,
            :size_threshold_ignore => String[], :example_size_threshold => nothing,
            :search_size_threshold_warn => nothing, :inventory_version => "1.0",
        )
        declared = Base.kwarg_decl(only(methods(Documenter.HTML)))
        @test setdiff(declared, keys(samples)) == Symbol[]
        for kw in declared
            # edit_branch is Documenter's deprecated spelling of edit_link; they can't be combined
            base = kw in (:edit_link, :edit_branch) ? (;) : (; edit_link = nothing)
            @test (Material3(; base..., kw => samples[kw]) isa Material3)
        end
        @test Material3(; edit_link = nothing, prettyurls = false).html.prettyurls == false
    end

    @testset "Integration: Documenter.HTML options render" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        build_dir = joinpath(fixtures_dir, "build-options")
        isdir(build_dir) && rm(build_dir; recursive = true)
        makedocs(;
            sitename = "TestPackage.jl",
            format = Material3(
                theme = :ocean_depth, dark_mode = :toggle,
                lang = "en-GB",
                description = "A package for testing.",
                canonical = "https://example.org/TestPackage.jl/stable/",
                analytics = "G-TEST123",
                assets = [
                    "assets/extra.css",
                    asset("https://cdn.example.org/lib.js", class = :js),
                    Documenter.RawHTMLHeadContent("<meta name=\"x-test\" content=\"raw\">"),
                ],
                footer = "Maintained by [the team](https://example.org/team).",
                highlights = ["yaml"],
                sidebar_sitename = false,
                edit_link = "main",
                collapselevel = 1,
                example_size_threshold = 64,
                warn_outdated = false,
                mathengine = Documenter.KaTeX(Dict(:macros => Dict("\\RR" => "\\mathbb{R}"))),
                inventory_version = "1.2.3",
            ),
            modules = [MaterialDocs],
            pages = ["Home" => "index.md", "Reference" => ["API" => "api.md", "Outputs" => "outputs.md"]],
            root = fixtures_dir, source = "src", build = "build-options",
            warnonly = true,
        )
        index_html = read(joinpath(build_dir, "index.html"), String)
        api_html = read(joinpath(build_dir, "api", "index.html"), String)

        # REQ-P2
        @test contains(index_html, "<html lang=\"en-GB\"")
        # REQ-P3
        @test contains(index_html, "<meta name=\"description\" content=\"A package for testing.\">")
        @test contains(index_html, "<meta property=\"og:description\" content=\"A package for testing.\">")
        # REQ-P4
        @test contains(index_html, "<link rel=\"canonical\" href=\"https://example.org/TestPackage.jl/stable/\">")
        @test contains(api_html, "<link rel=\"canonical\" href=\"https://example.org/TestPackage.jl/stable/api/\">")
        @test contains(index_html, "<meta property=\"og:image\" content=\"https://example.org/TestPackage.jl/stable/assets/preview.png\">")
        # REQ-P5
        @test contains(index_html, "https://www.googletagmanager.com/gtag/js?id=G-TEST123")
        @test contains(index_html, "gtag('config', 'G-TEST123'")
        # REQ-P6: order preserved, local paths relative to the page
        css_at = findfirst("<link rel=\"stylesheet\" href=\"../assets/extra.css\">", api_html)
        js_at = findfirst("<script src=\"https://cdn.example.org/lib.js\"></script>", api_html)
        raw_at = findfirst("<meta name=\"x-test\" content=\"raw\">", api_html)
        @test css_at !== nothing && js_at !== nothing && raw_at !== nothing
        @test first(css_at) < first(js_at) < first(raw_at)
        # REQ-P7
        @test contains(index_html, "Maintained by <a href=\"https://example.org/team\">the team</a>.")
        @test !contains(index_html, "Built with")
        # REQ-P8
        @test contains(api_html, "<img class=\"md-navbar-logo md-logo-light\" src=\"../assets/logo.svg\"")
        @test contains(api_html, "<img class=\"md-navbar-logo md-logo-dark\" src=\"../assets/logo-dark.svg\"")
        # REQ-S5
        @test contains(index_html, "highlight.js/11.9.0/languages/yaml.min.js")
        # REQ-S6
        @test !contains(index_html, "md-navbar-title")
    end

    # REQ-P9 (Must): Where the page source is in a known remote repository, and
    #   neither `edit_link = nothing` nor `disable_git = true`, each page shall
    #   link to its source at `edit_link` ("Edit source on <host>"), or at the
    #   current commit for `edit_link = :commit` ("View source on <host>").
    # REQ-P10 (Must): Where a page sets an absolute `@meta EditURL`, the page
    #   shall link "View source" to it; where `EditURL = nothing`, no link.
    # REQ-P11 (Must): Each page shall link to the previous and next pages in
    #   navigation order, labelled with their titles.
    @testset "Integration: edit links and page navigation" begin
        build_dir = joinpath(@__DIR__, "fixtures", "build-options")
        index_html = read(joinpath(build_dir, "index.html"), String)
        api_html = read(joinpath(build_dir, "api", "index.html"), String)
        out_html = read(joinpath(build_dir, "outputs", "index.html"), String)

        @test contains(index_html, "href=\"https://github.com/mthelm85/MaterialDocs.jl/blob/main/test/fixtures/src/index.md\" title=\"Edit source on GitHub\"")
        @test contains(out_html, "href=\"https://example.org/outputs-source.md\" title=\"View source\"")

        @test contains(index_html, "<a class=\"md-page-nav-next\" href=\"./api/\">")
        @test !contains(index_html, "md-page-nav-prev")
        @test contains(api_html, "<a class=\"md-page-nav-prev\" href=\"../\">")
        @test contains(api_html, "<a class=\"md-page-nav-next\" href=\"../outputs/\">")
        @test contains(api_html, "<span class=\"md-page-nav-title\">Outputs</span>")
        @test !contains(out_html, "md-page-nav-next")
    end

    # REQ-P12 (Must): A navigation section nested at level `collapselevel` or
    #   deeper (top level is 1) shall start collapsed, unless it contains the
    #   current page.
    @testset "Integration: collapselevel" begin
        build_dir = joinpath(@__DIR__, "fixtures", "build-options")
        index_html = read(joinpath(build_dir, "index.html"), String)
        api_html = read(joinpath(build_dir, "api", "index.html"), String)
        @test contains(index_html, "<div class=\"md-nav-section md-nav-collapsed\">")
        @test contains(api_html, "<div class=\"md-nav-section\">")
        @test !contains(api_html, "md-nav-collapsed")
    end

    # REQ: The sidebar shall mark the current page's link as active.
    @testset "Integration: current page is highlighted in the sidebar" begin
        api_html = read(joinpath(@__DIR__, "fixtures", "build", "api", "index.html"), String)
        @test contains(api_html, "<a href=\"../api/\" class=\"md-nav-active\">API</a>")
        @test count("md-nav-active", api_html) == 1
    end

    # REQ-P14 (Must): When an @example image representation is at least
    #   `example_size_threshold` bytes, the writer shall write it to a file beside
    #   the page and link it, instead of embedding it.
    # REQ-P15 (Must): When an @example text/html representation is at least
    #   `example_size_threshold` bytes, the writer shall use an image
    #   representation if one exists, otherwise the HTML, and warn once per build.
    @testset "Integration: example_size_threshold" begin
        build_dir = joinpath(@__DIR__, "fixtures", "build-options")
        out_html = read(joinpath(build_dir, "outputs", "index.html"), String)

        # The 4-byte JPEG stays inline; the ~90-byte SVG goes to a file
        @test contains(out_html, "<img src=\"data:image/jpeg;base64,")
        svg = match(r"<img src=\"([0-9a-f]{8}\.svg)\"", out_html)
        @test svg !== nothing
        @test svg !== nothing && isfile(joinpath(build_dir, "outputs", svg[1]))
        # Large HTML with a PNG alternative uses the PNG; HTML-only stays HTML
        @test !contains(out_html, "<table class=\"big-html-png\">")
        @test contains(out_html, "<img src=\"data:image/png;base64,")
        @test contains(out_html, "<table class=\"big-html-only\">")

        # Main build uses the 8 KiB default: everything inline
        main_html = read(joinpath(@__DIR__, "fixtures", "build", "outputs", "index.html"), String)
        @test contains(main_html, "<table class=\"big-html-png\">")
        @test contains(main_html, "data:image/svg+xml;base64,")
    end

    # REQ-P16 (Must): When a page's HTML exceeds `size_threshold_warn`, the build
    #   shall warn; when it exceeds `size_threshold`, the build shall fail with
    #   Documenter's HTMLSizeThresholdError, unless the page is listed in
    #   `size_threshold_ignore`.
    # REQ-P17 (Must): When the search index exceeds `search_size_threshold_warn`,
    #   the build shall warn.
    @testset "Integration: size thresholds" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        build_small(; kw...) = makedocs(;
            sitename = "TestPackage.jl", format = Material3(; edit_link = nothing, kw...),
            modules = [MaterialDocs], pages = ["Home" => "index.md"],
            root = fixtures_dir, source = "src", build = "build-size",
            warnonly = true, checkdocs = :none, doctest = false,
        )
        # Every .md file in src/ is rendered, not only those listed in `pages`
        @test_throws Documenter.HTMLWriter.HTMLSizeThresholdError build_small(size_threshold = 2048, size_threshold_warn = 1024)
        @test_logs (:warn, r"size_threshold_warn") match_mode = :any build_small(size_threshold_warn = 1024)
        @test (build_small(size_threshold = 2048, size_threshold_warn = 1024, size_threshold_ignore = ["index.md", "api.md", "outputs.md"]); true)
        @test_logs (:warn, r"search_size_threshold_warn") match_mode = :any build_small(search_size_threshold_warn = 16)
        rm(joinpath(fixtures_dir, "build-size"); recursive = true, force = true)
    end

    # REQ-P18 (Must): Where `warn_outdated` is true (the default), each page shall
    #   load the outdated-version banner, which shows when the deployed version is
    #   not the newest; where false, the page shall not.
    # REQ-P19 (Should): Each build shall write `.documenter-siteinfo.json`, as
    #   Documenter.HTML does.
    @testset "Integration: warn_outdated and siteinfo" begin
        main_html = read(joinpath(@__DIR__, "fixtures", "build", "index.html"), String)
        options_html = read(joinpath(@__DIR__, "fixtures", "build-options", "index.html"), String)
        @test contains(main_html, "<body data-warn-outdated>")
        @test contains(options_html, "<body>")
        @test !contains(options_html, "data-warn-outdated")

        js = read(joinpath(@__DIR__, "fixtures", "build", "assets", "materialdocs.js"), String)
        @test contains(js, "DOCUMENTER_NEWEST")
        @test contains(js, "md-outdated-banner")

        siteinfo = joinpath(@__DIR__, "fixtures", "build", ".documenter-siteinfo.json")
        @test isfile(siteinfo) && contains(read(siteinfo, String), "documenter_version")
    end

    # REQ-M7 (Must): The writer shall render an @repl block's inputs and outputs.
    # REQ-S7 (Should): Material3 shall declare ANSI color support to Documenter,
    #   so that where `ansicolor` is true (the default) @repl and @example output
    #   keeps its colors, rendered with theme-aware ANSI color tokens.
    @testset "Integration: @repl blocks and ANSI color" begin
        index_html = read(joinpath(@__DIR__, "fixtures", "build", "index.html"), String)
        @test contains(index_html, "<code class=\"language-julia-repl md-repl-part\">julia&gt; 1 + 1</code>")
        @test contains(index_html, "<code class=\"nohighlight ansi md-repl-part\">2</code>")
        # Both output paths go through the ANSI renderer. (Whether the captured
        # output contains escapes depends on Julia's --color setting, as with
        # Documenter.HTML, so the conversion itself is tested directly.)
        # With `julia --color=yes` (as on CI) the text arrives wrapped in a color span
        @test occursin(r"<code class=\"nohighlight ansi md-repl-part\">(<span class=\"sgr31\">)?repl-red", index_html)
        @test occursin(r"<pre class=\"md-output md-output-text\"><code class=\"nohighlight ansi\">(<span class=\"sgr33\">)?example-yellow", index_html)
        @test MaterialDocs._ansi_html("\e[31mred\e[39m <b>", "ansi") ==
              "<code class=\"ansi\"><span class=\"sgr31\">red</span> &lt;b&gt;</code>"

        @test Documenter.writer_supports_ansicolor(Material3())
        @test Material3().ansicolor == true
        @test Material3(ansicolor = false).ansicolor == false

        m3 = Material3(theme = :ocean_depth, dark_mode = :toggle)
        light, dark = hex_scheme_pair(m3.theme.seed)
        css = MaterialDocs.build_css(m3.theme, light, dark, m3)
        @test contains(css, "--md-ansi-red:")
        @test contains(css, "--md-ansi-bright-cyan:")
        @test contains(css, ".ansi .sgr31")
    end

    @testset "Footer defaults" begin
        # REQ-P7: default attribution, and `nothing` removes the footer text
        @test contains(Documenter.MDFlatten.mdflatten(Material3().html.footer), "MaterialDocs.jl")
        @test Material3(footer = nothing).html.footer === nothing
    end

    # REQ-M5 (Must): When a build completes, the writer shall write an
    #   `objects.inv` inventory listing the same pages, labels and docstrings,
    #   at the same URIs, as Documenter.HTML writes for the same sources.
    # REQ-M6 (Must): Where `inventory_version` is set, the inventory header
    #   shall carry that version.
    @testset "Integration: objects.inv matches Documenter.HTML" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        html_build = joinpath(fixtures_dir, "build-html")
        isdir(html_build) && rm(html_build; recursive = true)
        makedocs(;
            sitename = "TestPackage.jl",
            format = Documenter.HTML(inventory_version = "1.2.3"),
            modules = [MaterialDocs],
            pages = ["Home" => "index.md", "API" => "api.md", "Outputs" => "outputs.md"],
            root = fixtures_dir, source = "src", build = "build-html",
            warnonly = true,
        )

        function read_inventory(path)
            bytes = read(path)
            header_end = 0
            for _ in 1:4
                header_end = findnext(==(UInt8('\n')), bytes, header_end + 1)
            end
            header = split(String(bytes[1:header_end]), '\n'; keepempty = false)
            body = String(transcode(CodecZlib.ZlibDecompressor, bytes[header_end+1:end]))
            return header, sort(split(body, '\n'; keepempty = false))
        end

        ours_path = joinpath(fixtures_dir, "build", "objects.inv")
        @test isfile(ours_path)
        ours_header, ours = read_inventory(ours_path)
        theirs_header, theirs = read_inventory(joinpath(html_build, "objects.inv"))

        @test ours_header == theirs_header
        @test "# Version: 1.2.3" in ours_header
        @test !isempty(ours)
        @test ours == theirs
        @test any(startswith("MaterialDocs.Material3 jl:type 1 api/#"), ours)
    end

    @testset "Integration: index.html structure" begin
        index_html = read(joinpath(@__DIR__, "fixtures", "build", "index.html"), String)

        # Document structure
        @test contains(index_html, "<!doctype html>")
        @test contains(index_html, "<html lang=\"en\">")
        @test contains(index_html, "<title>Welcome to TestPackage.jl — TestPackage.jl</title>")

        # Navbar
        @test contains(index_html, "class=\"md-navbar\"")
        @test contains(index_html, "md-navbar-title")
        @test contains(index_html, "md-theme-toggle")  # toggle mode
        @test contains(index_html, "md-hamburger")      # mobile hamburger
        @test contains(index_html, "md-search-btn")     # MD3 search bar
        @test contains(index_html, "md-search-bar")
        @test contains(index_html, "md-version")        # version selector shell
        @test contains(index_html, "siteinfo.js")       # deploydocs version metadata
        @test contains(index_html, "../versions.js")

        # Sidebar nav
        @test contains(index_html, "class=\"md-sidebar\"")
        @test contains(index_html, "href=\"./\"")   # Home link (prettyurl root)
        @test contains(index_html, "href=\"./api/\"")  # API link (prettyurl)

        # Content area
        @test contains(index_html, "class=\"md-article\"")

        # Headings with anchors
        @test contains(index_html, "class=\"md-heading\"")
        @test contains(index_html, "class=\"md-heading-anchor\"")

        # Inline formatting
        @test contains(index_html, "<strong>MaterialDocs.jl</strong>")
        @test contains(index_html, "<em>italic text</em>")
        @test contains(index_html, "class=\"md-code-inline\"")

        # Code block with copy button
        @test contains(index_html, "class=\"md-code-block\"")
        @test contains(index_html, "class=\"md-copy-btn\"")
        @test contains(index_html, "language-julia")

        # Links
        @test contains(index_html, "href=\"./api/\"")  # cross-page link
        @test contains(index_html, "href=\"https://julialang.org\"")

        # Blockquote
        @test contains(index_html, "class=\"md-blockquote\"")

        # Thematic break
        @test contains(index_html, "class=\"md-hr\"")

        # Lists
        @test contains(index_html, "class=\"md-list-tight\"")
        @test contains(index_html, "<ol")
        @test contains(index_html, "<ul")

        # Table
        @test contains(index_html, "class=\"md-table-wrap\"")
        @test contains(index_html, "class=\"md-table\"")
        @test contains(index_html, "text-align:left")
        @test contains(index_html, "text-align:center")
        @test contains(index_html, "text-align:right")

        # Admonitions
        @test contains(index_html, "md-admonition-note")
        @test contains(index_html, "md-admonition-warning")
        @test contains(index_html, "md-admonition-tip")
        @test contains(index_html, "md-admonition-danger")
        @test contains(index_html, "class=\"md-admonition-title\"")
        @test contains(index_html, "class=\"md-admonition-body\"")

        # Math
        @test contains(index_html, "md-math-inline")
        @test contains(index_html, "md-math-display")
        @test contains(index_html, "\\(e = mc^2\\)")
        @test contains(index_html, "\\[")

        # Footnotes
        @test contains(index_html, "class=\"md-footnote-ref\"")
        @test contains(index_html, "class=\"md-footnote\"")
        @test contains(index_html, "id=\"fn-1\"")

        # TOC rail
        @test contains(index_html, "class=\"md-toc\"")
        @test contains(index_html, "class=\"md-toc-title\"")
        @test contains(index_html, "class=\"md-toc-link md-toc-h2\"")
        @test contains(index_html, "class=\"md-toc-link md-toc-h3\"")

        # Footer
        @test contains(index_html, "class=\"md-footer\"")
        @test contains(index_html, "Documenter.jl")
        @test contains(index_html, "MaterialDocs.jl")

        # Assets
        @test contains(index_html, "materialdocs.css")
        @test contains(index_html, "materialdocs.js")
        @test contains(index_html, "fonts.googleapis.com")
    end

    @testset "Integration: api.html structure" begin
        api_html = read(joinpath(@__DIR__, "fixtures", "build", "api", "index.html"), String)

        # Page title
        @test contains(api_html, "<title>API Reference — TestPackage.jl</title>")

        # Docstrings
        @test contains(api_html, "class=\"md-docstring\"")
        @test contains(api_html, "class=\"md-docstring-binding\"")
        @test contains(api_html, "class=\"md-docstring-content\"")

        # Root prefix for nested prettyurl (api/index.html → ../ to reach root)
        @test contains(api_html, "href=\"../assets/materialdocs.css?v=")
    end

    # ── Content real packages rely on ──────────────────────────────────
    #
    # REQ-M1 (Must): Where a page contains math, the page shall load KaTeX and
    #   typeset every math element.
    # REQ-M2 (Must): Where a page contains no math, the page shall not load KaTeX.
    # REQ-M3 (Must): When an @example result's richest representation is
    #   image/webp, image/gif or image/jpeg, the writer shall render it as an image.
    # REQ-M4 (Must): When an @example result's richest representation is
    #   text/latex or text/markdown, the writer shall render it as math or
    #   formatted Markdown rather than plain text.
    # REQ-S1 (Should): When an @example result is SVG, the writer shall embed it
    #   as an image, so element ids in one plot cannot collide with another's.
    # REQ-S2 (Should): When the writer meets an element type it cannot render,
    #   it shall render the element's children and warn once per type.
    # REQ-S3 (Should): When a page uses `[text](@id name)`, the writer shall
    #   emit an element with that id.
    # REQ-S4 (Should): The writer shall take a code block's highlight language
    #   from the first word of its info string.

    @testset "Integration: math is typeset" begin
        build_dir = joinpath(@__DIR__, "fixtures", "build")
        index_html = read(joinpath(build_dir, "index.html"), String)
        api_html = read(joinpath(build_dir, "api", "index.html"), String)

        @test contains(index_html, "katex.min.js")
        @test contains(index_html, "katex.min.css")
        @test contains(index_html, "katex.render(")
        @test !contains(api_html, "katex")
    end

    # REQ-P13 (Must): Where a page contains math, the page shall typeset it with
    #   the `mathengine` given: KaTeX with its config's render options (macros
    #   etc.), MathJax2 or MathJax3 with their config and `url`, or nothing at
    #   all for `mathengine = nothing`.
    @testset "mathengine scripts" begin
        katex = MaterialDocs._math_scripts(Documenter.KaTeX(Dict(:macros => Dict("\\RR" => "\\mathbb{R}"))))
        @test contains(katex, "katex.min.js")
        @test contains(katex, "katex.render(")
        @test contains(katex, "\"macros\":{\"\\\\RR\":\"\\\\mathbb{R}\"}")
        @test !contains(katex, "delimiters")  # auto-render option, not a render option

        mj3 = MaterialDocs._math_scripts(Documenter.MathJax3())
        @test contains(mj3, "window.MathJax = {")
        @test contains(mj3, "mathjax/3.2.2/es5/tex-svg-full.js")
        @test contains(MaterialDocs._math_scripts(Documenter.MathJax3(; url = "https://example.org/mj.js")),
                       "https://example.org/mj.js")

        mj2 = MaterialDocs._math_scripts(Documenter.MathJax2())
        @test contains(mj2, "MathJax.Hub.Config(")
        @test contains(mj2, "mathjax/2.7.9/MathJax.js?config=TeX-AMS_HTML")

        @test MaterialDocs._math_scripts(nothing) == ""

        # Config text can't close the <script> element early
        @test !contains(MaterialDocs._math_scripts(Documenter.KaTeX(Dict(:macros => Dict("\\x" => "</script>")))),
                        "</script><")
    end

    @testset "Integration: mathengine config reaches the page" begin
        index_html = read(joinpath(@__DIR__, "fixtures", "build-options", "index.html"), String)
        @test contains(index_html, "\"macros\":{\"\\\\RR\":\"\\\\mathbb{R}\"}")
    end

    @testset "Integration: rich @example outputs" begin
        out_html = read(joinpath(@__DIR__, "fixtures", "build", "outputs", "index.html"), String)

        @test contains(out_html, "<img src=\"data:image/jpeg;base64,/9j/4A==\"")
        @test contains(out_html, "<img src=\"data:image/gif;base64,")
        @test contains(out_html, "<img src=\"data:image/webp;base64,")

        @test contains(out_html, "src=\"data:image/svg+xml;base64,")
        @test !contains(out_html, "<rect id=\"clip1\"")

        @test contains(out_html, "md-math-display")
        @test contains(out_html, "\\alpha^2 + \\beta^2")
        @test contains(out_html, "katex.min.js")

        @test contains(out_html, "<strong>markdown</strong>")
        # No result on this page should fall back to its text/plain form
        @test !contains(out_html, "md-output-text")
    end

    @testset "Integration: inline anchors and code languages" begin
        out_html = read(joinpath(@__DIR__, "fixtures", "build", "outputs", "index.html"), String)

        @test contains(out_html, "<span id=\"inline-anchor\">This sentence is a link target</span>")
        @test contains(out_html, "<code class=\"language-julia\">")
        @test !contains(out_html, "language-julia filter")
    end

    @testset "Unsupported elements warn once and keep their content" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        doc = Documenter.Document(; root = fixtures_dir, source = "src", build = "build",
                                  format = [Material3()], remotes = nothing)
        page = Documenter.Page(joinpath(fixtures_dir, "src", "index.md"),
                               joinpath(fixtures_dir, "build", "index.html"), fixtures_dir)
        ctx = MaterialDocs.DomifyContext(IOBuffer(), doc, page, "", Material3())

        node = Documenter.MarkdownAST.Node(UnknownFixtureElement())
        push!(node.children, Documenter.MarkdownAST.Node(Documenter.MarkdownAST.Text("kept text")))

        @test_logs (:warn, r"UnknownFixtureElement") MaterialDocs.domify(ctx, node)
        @test contains(String(take!(ctx.io)), "kept text")
        # Second encounter in the same build: no further warning
        @test_logs MaterialDocs.domify(ctx, node)
    end

    @testset "Utility: _nav_href" begin
        # prettyurls
        @test MaterialDocs._nav_href("index.md", true) == ""
        @test MaterialDocs._nav_href("api.md", true) == "api/"
        @test MaterialDocs._nav_href("guide/intro.md", true) == "guide/intro/"

        # no prettyurls
        @test MaterialDocs._nav_href("index.md", false) == "index.html"
        @test MaterialDocs._nav_href("api.md", false) == "api.html"
    end

    # ─────────────────────────────────────────────────────────────────
    # Phase 7: Search Index
    # ─────────────────────────────────────────────────────────────────

    @testset "Integration: @index and @contents render entries" begin
        # Documenter fills IndexNode.elements with (object, doc, page, mod, cat)
        # tuples and ContentsNode.elements with (order, page, anchor) tuples —
        # not Pairs. Rendering used to test `isa Pair` and so emitted nothing.
        api_html = read(joinpath(@__DIR__, "fixtures", "build", "api", "index.html"), String)

        # The index lists the documented bindings, linked
        @test contains(api_html, "md-index")
        @test !contains(api_html, "<div class=\"md-index\">
<ul>
</ul>")
        # Entries link to the docstring anchors DocsNode emits. On the same
        # page that is a bare fragment, so no path precedes the '#'.
        @test contains(api_html, "<li><a href=\"#MaterialDocs.Material3\"><code>MaterialDocs.Material3</code></a></li>")
        @test contains(api_html, "<li><a href=\"#MaterialDocs.load_theme\"><code>MaterialDocs.load_theme</code></a></li>")
        # Every index target actually exists as an anchor on the page
        for name in ("MaterialDocs.Material3", "MaterialDocs.ThemeConfig", "MaterialDocs.load_theme")
            @test contains(api_html, "id=\"$name\"")
        end
    end

    @testset "Integration: search index" begin
        build_dir = joinpath(@__DIR__, "fixtures", "build")
        index_path = joinpath(build_dir, "assets", "search-index.json")

        # Search index file should exist
        @test isfile(index_path)

        index_json = read(index_path, String)

        # Should be valid JSON array (starts with [ and ends with ])
        @test startswith(index_json, "[")
        @test endswith(index_json, "]")

        # Should contain entries from our pages
        @test contains(index_json, "\"title\":")
        @test contains(index_json, "\"text\":")
        @test contains(index_json, "\"href\":")
        @test contains(index_json, "\"section\":")

        # Index page content
        @test contains(index_json, "Welcome to TestPackage.jl")

        # API page content
        @test contains(index_json, "API Reference")

        # Hrefs should use prettyurl format
        @test contains(index_json, "api/")
    end

    @testset "JSON escaping" begin
        escaped = MaterialDocs._json_escape("hello \"world\"\nnewline\\slash")
        @test escaped == "hello \\\"world\\\"\\nnewline\\\\slash"
        @test !contains(escaped, "\n")  # actual newline
    end

    @testset "Text truncation" begin
        short = "hello world"
        @test MaterialDocs._truncate_text(short, 300) == short

        long = "word " ^ 100  # 500 chars
        truncated = MaterialDocs._truncate_text(long, 50)
        @test length(truncated) <= 55  # 50 + "…" + some slack
        @test endswith(truncated, "…")
    end

    # ─────────────────────────────────────────────────────────────────
    # Phase 4: Theme TOML Configuration
    # ─────────────────────────────────────────────────────────────────

    @testset "TOML round-trip" begin
        toml_dir = joinpath(@__DIR__, "fixtures", "toml_test")
        isdir(toml_dir) || mkpath(toml_dir)
        toml_path = joinpath(toml_dir, ".materialdocs.toml")

        # Create a ThemeConfig with all fields populated
        original = ThemeConfig(
            name = "test-theme",
            seed = "#1565C0",
            secondary_seed = "#00897B",
            tertiary_seed = "#E65100",
            display_font = "Fira Sans",
            body_font = "Source Sans 3",
            code_font = "JetBrains Mono",
            corner_radius = :default,
            custom_colors = Dict("primary" => "#112233", "surface" => "#FAFAFA"),
        )

        # Write
        save_theme(original, toml_path)
        @test isfile(toml_path)

        # Read back
        loaded = load_theme(toml_path)
        @test loaded.name == original.name
        @test loaded.seed == original.seed
        @test loaded.secondary_seed == original.secondary_seed
        @test loaded.tertiary_seed == original.tertiary_seed
        @test loaded.display_font == original.display_font
        @test loaded.body_font == original.body_font
        @test loaded.code_font == original.code_font
        @test loaded.corner_radius == original.corner_radius
        @test loaded.custom_colors == original.custom_colors

        # Clean up
        rm(toml_dir; recursive=true)
    end

    @testset "TOML minimal config" begin
        toml_dir = joinpath(@__DIR__, "fixtures", "toml_test")
        isdir(toml_dir) || mkpath(toml_dir)
        toml_path = joinpath(toml_dir, ".materialdocs.toml")

        # Write a minimal config (no secondary/tertiary, no custom colors)
        minimal = ThemeConfig(seed = "#2E7D32")
        save_theme(minimal, toml_path)

        # Read back — should fill defaults
        loaded = load_theme(toml_path)
        @test loaded.seed == "#2E7D32"
        @test loaded.secondary_seed === nothing
        @test loaded.tertiary_seed === nothing
        @test loaded.display_font == "Roboto"
        @test loaded.body_font == "Roboto"
        @test loaded.code_font == "Roboto Mono"
        @test loaded.corner_radius == :default
        @test isempty(loaded.custom_colors)

        rm(toml_dir; recursive=true)
    end

    @testset "TOML file content is valid" begin
        toml_dir = joinpath(@__DIR__, "fixtures", "toml_test")
        isdir(toml_dir) || mkpath(toml_dir)
        toml_path = joinpath(toml_dir, ".materialdocs.toml")

        tc = ThemeConfig(
            name = "readable",
            seed = "#006B5E",
            display_font = "Inter",
            body_font = "Inter",
            code_font = "Fira Code",
            corner_radius = :pill,
        )
        save_theme(tc, toml_path)

        content = read(toml_path, String)
        @test contains(content, "[theme]")
        @test contains(content, "[theme.fonts]")
        @test contains(content, "[theme.shape]")
        @test contains(content, "seed = \"#006B5E\"")
        @test contains(content, "corner_radius = \"pill\"")
        @test contains(content, "display = \"Inter\"")

        # Should NOT contain custom_colors section when empty
        @test !contains(content, "[theme.custom_colors]")

        # Header comment
        @test contains(content, "Generated by MaterialDocs.jl")

        rm(toml_dir; recursive=true)
    end

    @testset "TOML error handling" begin
        # Non-existent file
        @test_throws ArgumentError load_theme("nonexistent.toml")

        # Invalid TOML content
        bad_toml = joinpath(@__DIR__, "fixtures", "toml_test", "bad.toml")
        isdir(dirname(bad_toml)) || mkpath(dirname(bad_toml))
        Base.write(bad_toml, "this is not valid toml {{{}}")
        @test_throws ArgumentError load_theme(bad_toml)

        # Invalid hex color
        bad_hex_toml = joinpath(@__DIR__, "fixtures", "toml_test", "bad_hex.toml")
        Base.write(bad_hex_toml, """
        [theme]
        seed = "not-a-color"
        """)
        @test_throws ArgumentError load_theme(bad_hex_toml)

        # Invalid corner_radius
        bad_shape_toml = joinpath(@__DIR__, "fixtures", "toml_test", "bad_shape.toml")
        Base.write(bad_shape_toml, """
        [theme]
        seed = "#FF0000"
        [theme.shape]
        corner_radius = "invalid"
        """)
        @test_throws ArgumentError load_theme(bad_shape_toml)

        rm(joinpath(@__DIR__, "fixtures", "toml_test"); recursive=true)
    end

    @testset "find_theme_toml" begin
        toml_dir = joinpath(@__DIR__, "fixtures", "toml_test")
        isdir(toml_dir) || mkpath(toml_dir)

        # No file → nothing
        @test find_theme_toml(toml_dir) === nothing

        # .materialdocs.toml found
        toml_path = joinpath(toml_dir, ".materialdocs.toml")
        Base.write(toml_path, "[theme]\nseed = \"#FF0000\"\n")
        result = find_theme_toml(toml_dir)
        @test result == toml_path

        # Also supports materialdocs.toml (no dot prefix)
        rm(toml_path)
        alt_path = joinpath(toml_dir, "materialdocs.toml")
        Base.write(alt_path, "[theme]\nseed = \"#00FF00\"\n")
        result2 = find_theme_toml(toml_dir)
        @test result2 == alt_path

        rm(toml_dir; recursive=true)
    end

    @testset "TOML special characters in strings" begin
        toml_dir = joinpath(@__DIR__, "fixtures", "toml_test")
        isdir(toml_dir) || mkpath(toml_dir)
        toml_path = joinpath(toml_dir, ".materialdocs.toml")

        # Font name with special chars
        tc = ThemeConfig(name = "theme \"quoted\"", display_font = "Font's Name")
        save_theme(tc, toml_path)
        loaded = load_theme(toml_path)
        @test loaded.name == "theme \"quoted\""
        @test loaded.display_font == "Font's Name"

        rm(toml_dir; recursive=true)
    end


    # ─────────────────────────────────────────────────────────────────
    # Phase 8: Theme Editor
    # ─────────────────────────────────────────────────────────────────

    @testset "Editor panel HTML" begin
        theme = resolve_theme(:ocean_depth)
        html = MaterialDocs._editor_panel_html(theme)

        # Should contain editor UI elements
        @test contains(html, "id=\"ed-seed\"")
        @test contains(html, "id=\"ed-secondary\"")
        @test contains(html, "id=\"ed-tertiary\"")
        @test contains(html, "id=\"ed-display-font\"")
        @test contains(html, "id=\"ed-body-font\"")
        @test contains(html, "id=\"ed-code-font\"")
        @test contains(html, "id=\"ed-corner-radius\"")
        @test contains(html, "id=\"ed-toggle-dark\"")

        # Should have initial theme values
        @test contains(html, theme.seed)
        sec = something(theme.secondary_seed, theme.seed)
        ter = something(theme.tertiary_seed, theme.seed)
        @test contains(html, sec)
        @test contains(html, ter)

        # Should contain export button and TOML preview
        @test contains(html, "ed-copy-toml")
        @test contains(html, "ed-toml-preview")

        # Panel structure
        @test contains(html, "md-editor-panel")
        @test contains(html, "md-editor-tab")
        @test contains(html, "md-editor-body")
    end

    @testset "Editor panel JS" begin
        theme = resolve_theme(:ocean_depth)
        js = MaterialDocs._editor_panel_js(theme)

        # The color engine is NOT duplicated in JS any more — the panel asks
        # the Julia server for the scheme so preview and build cannot diverge.
        @test !contains(js, "hexToHCT")
        @test !contains(js, "cam16FromRGB")
        @test !contains(js, "solveHCT")
        @test contains(js, "__scheme__")
        @test contains(js, "fetchScheme")
        @test contains(js, "generateTOML")
        @test contains(js, "applyColors")
        @test contains(js, "applyFonts")
        @test contains(js, "applyShape")

        # Should contain theme seed values
        @test contains(js, theme.seed)
    end

    @testset "Editor injection" begin
        html = "<html><body><h1>Test</h1></body></html>"
        panel_html = "<div>PANEL</div>"
        injected = MaterialDocs._inject_editor(html, panel_html)

        # Panel should be injected before </body>
        @test contains(injected, "PANEL")
        @test contains(injected, "__editor__.js")
        # Original content preserved
        @test contains(injected, "<h1>Test</h1>")
    end

    @testset "Editor MIME types" begin
        @test contains(MaterialDocs._mime_type("style.css"), "text/css")
        @test contains(MaterialDocs._mime_type("app.js"), "javascript")
        @test MaterialDocs._mime_type("image.png") == "image/png"
        @test MaterialDocs._mime_type("data.json") == "application/json; charset=utf-8"
    end

    @testset "Editor URL decode" begin
        @test MaterialDocs._url_decode("/hello%20world") == "/hello world"
        @test MaterialDocs._url_decode("/path/to/file") == "/path/to/file"
    end

    @testset "Editor font options" begin
        opts = MaterialDocs._font_options("Inter", :display)
        @test contains(opts, "selected")
        @test contains(opts, "Inter")
        @test contains(opts, "Roboto")

        # Custom font gets added
        opts_custom = MaterialDocs._font_options("CustomFont", :body)
        @test contains(opts_custom, "CustomFont")
        @test contains(opts_custom, "selected")
    end

    @testset "Repo link from a Documenter URL template" begin
        # Documenter turns a `repo = "…/blob/{commit}{path}#{line}"` string into
        # a Remotes.URL, whose repourl() is nothing. BestieTemplate generates
        # exactly that, so derive the repository root from the template instead.
        f = MaterialDocs._repo_root_from_template
        @test f("https://github.com/o/r.jl/blob/{commit}{path}#{line}") == "https://github.com/o/r.jl"
        @test f("https://gitlab.com/o/r.jl/-/blob/{commit}{path}#{line}") == "https://gitlab.com/o/r.jl"
        @test f("https://bitbucket.org/o/r/src/{commit}{path}#{line}") == "https://bitbucket.org/o/r"
        # Nothing recognisable to truncate at — better no link than a wrong one
        @test f("https://example.com/something") === nothing
        @test f("") === nothing
    end

    @testset "Editor server binds loopback by default" begin
        # A local preview server must not be reachable from the rest of the
        # network unless the caller explicitly asks for that.
        @test MaterialDocs.EDITOR_DEFAULT_HOST == IPv4(127, 0, 0, 1)
        @test :host in Base.kwarg_decl(first(methods(MaterialDocs.editor)))

        server = MaterialDocs._editor_listen(MaterialDocs.EDITOR_DEFAULT_HOST, 0)
        try
            addr, port = getsockname(server)
            @test addr == IPv4(127, 0, 0, 1)
            @test port > 0
        finally
            close(server)
        end

        # Opting in to another interface is still possible, and is reported
        @test MaterialDocs._is_loopback(IPv4(127, 0, 0, 1))
        @test MaterialDocs._is_loopback(IPv6(0, 0, 0, 0, 0, 0, 0, 1))
        @test !MaterialDocs._is_loopback(IPv4(0, 0, 0, 0))
        @test !MaterialDocs._is_loopback(IPv4(192, 168, 1, 10))
    end

    @testset "Editor query parsing" begin
        q = MaterialDocs._parse_query("seed=%236750A4&dark=true&secondary=")
        @test q["seed"] == "#6750A4"
        @test q["dark"] == "true"
        @test q["secondary"] == ""
        @test isempty(MaterialDocs._parse_query(""))
    end

    @testset "Editor scheme route" begin
        theme = resolve_theme(:ocean_depth)

        # The route returns exactly what the build would generate
        json = MaterialDocs._scheme_json("seed=%236750A4", theme)
        expected = hex_scheme_pair("#6750A4")[1]
        for (role, hex) in expected
            css = replace(String(role), '_' => '-')
            @test contains(json, "\"$css\":\"$hex\"")
        end

        # All 34 roles, not the 31 the old JS knew about
        @test length(collect(eachmatch(r"\"[a-z-]+\":", json))) == length(expected)

        # dark differs, and overrides are honoured
        @test MaterialDocs._scheme_json("seed=%236750A4&dark=true", theme) != json
        withsec = MaterialDocs._scheme_json("seed=%236750A4&secondary=%23FF0000", theme)
        @test withsec != json

        # Missing seed falls back to the theme's own
        @test MaterialDocs._scheme_json("", theme) ==
              MaterialDocs._scheme_json("seed=" * MaterialDocs._url_encode(theme.seed), theme)

        # A malformed seed is rejected rather than silently mis-rendered
        @test_throws ArgumentError MaterialDocs._scheme_json("seed=nonsense", theme)
    end

    @testset "Editor scheme to JS" begin
        scheme = Dict(:primary => "#FF0000", :on_primary => "#FFFFFF")
        js = MaterialDocs._scheme_to_js_object(scheme)
        @test contains(js, "\"on-primary\":\"#FFFFFF\"")
        @test contains(js, "\"primary\":\"#FF0000\"")
        @test startswith(js, "{")
        @test endswith(js, "}")
    end
end
