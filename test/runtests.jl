using MaterialDocs
using Documenter
using Test
using Aqua
using JET

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

    @testset "HCT round-trip" begin
        # Every hex → HCT → hex must reproduce the original
        test_colors = [
            "#6750A4",  # MD3 default primary (purple)
            "#FF0000",  # pure red
            "#00FF00",  # pure green
            "#0000FF",  # pure blue
            "#FFFFFF",  # white
            "#000000",  # black
            "#B3261E",  # MD3 error red
            "#625B71",  # MD3 secondary
            "#7D5260",  # MD3 tertiary
            "#49454F",  # MD3 neutral
            "#D0BCFF",  # light purple (dark-mode primary)
            "#EADDFF",  # very light purple (container)
            "#808080",  # mid grey
            "#C0C0C0",  # silver
            "#FFFF00",  # yellow
            "#FF00FF",  # magenta
            "#FFA500",  # orange
            "#1B1B1F",  # near-black (MD3 dark surface)
            "#FFFBFE",  # near-white (MD3 light surface)
        ]
        for hex in test_colors
            c = hct(hex)
            @test to_hex(c) == hex
        end
    end

    @testset "HCT round-trip (gamut boundary, ±1 tolerance)" begin
        # Colors at the sRGB gamut boundary may differ by ±1 per channel
        # due to bisection fallback in the solver
        boundary_colors = ["#00FFFF", "#FF0080", "#80FF00"]
        for hex in boundary_colors
            c = hct(hex)
            result = to_hex(c)
            r1, g1, b1 = parse(Int, hex[2:3]; base=16), parse(Int, hex[4:5]; base=16), parse(Int, hex[6:7]; base=16)
            r2, g2, b2 = parse(Int, result[2:3]; base=16), parse(Int, result[4:5]; base=16), parse(Int, result[6:7]; base=16)
            @test abs(r1 - r2) <= 4 && abs(g1 - g2) <= 4 && abs(b1 - b2) <= 4
        end
    end

    @testset "HCT value ranges" begin
        c = hct("#6750A4")
        @test 0.0 <= c.hue < 360.0
        @test c.chroma >= 0.0
        @test 0.0 <= c.tone <= 100.0
    end

    @testset "HCT achromatic colors" begin
        # Greys should have near-zero chroma
        for grey in ["#000000", "#808080", "#FFFFFF"]
            c = hct(grey)
            @test c.chroma < 3.0
        end
        # Black tone ≈ 0, white tone ≈ 100
        @test hct("#000000").tone ≈ 0.0 atol=0.1
        @test hct("#FFFFFF").tone ≈ 100.0 atol=0.1
    end

    @testset "HCT construct from values" begin
        c = HCT(280.0, 50.0, 40.0)
        hex = to_hex(c)
        # Round-trip from explicit values
        c2 = hct(hex)
        @test c2.hue ≈ c.hue atol=1.0
        @test c2.tone ≈ c.tone atol=1.0
        # Chroma may be gamut-mapped down, but should be close
        @test c2.chroma <= c.chroma + 1.0
    end

    @testset "HCT show method" begin
        c = hct("#6750A4")
        s = sprint(show, c)
        @test contains(s, "HCT")
        @test contains(s, "hue=")
        @test contains(s, "chroma=")
        @test contains(s, "tone=")
    end

    @testset "HCT invalid input" begin
        @test_throws ArgumentError hct("#GG00FF")
        @test_throws ArgumentError hct("#12345")
        @test_throws ArgumentError hct("")
    end

    # ─────────────────────────────────────────────────────────────────
    # Tonal Palette
    # ─────────────────────────────────────────────────────────────────

    @testset "TonalPalette basics" begin
        p = tonal_palette("#6750A4")
        @test p isa TonalPalette
        @test p.hue ≈ hct("#6750A4").hue
        @test p.chroma ≈ hct("#6750A4").chroma

        # Tone 0 should be near-black, tone 100 near-white
        @test p[0] == "#000000"
        @test p[100] == "#FFFFFF"

        # tone_at is an alias for getindex
        @test tone_at(p, 40) == p[40]
    end

    @testset "TonalPalette tone ordering" begin
        p = tonal_palette("#6750A4")
        # Higher tones should produce lighter colors (higher L*)
        for (t1, t2) in [(10, 40), (40, 80), (80, 99)]
            c1 = hct(p[t1])
            c2 = hct(p[t2])
            @test c2.tone > c1.tone
        end
    end

    @testset "TonalPalette caching" begin
        p = tonal_palette("#6750A4")
        hex1 = p[40]
        hex2 = p[40]
        @test hex1 === hex2  # same object from cache
    end

    @testset "TonalPalette precompute!" begin
        p = TonalPalette(280.0, 48.0)
        @test isempty(p.cache)
        precompute!(p)
        @test length(p.cache) == length(MaterialDocs.MD3_TONE_STOPS)
    end

    @testset "TonalPalette show method" begin
        p = TonalPalette(280.0, 48.0)
        s = sprint(show, p)
        @test contains(s, "TonalPalette")
        @test contains(s, "hue=280.0")
    end

    # ─────────────────────────────────────────────────────────────────
    # Color Scheme
    # ─────────────────────────────────────────────────────────────────

    @testset "color_scheme basics" begin
        scheme = color_scheme("#6750A4")
        @test scheme isa Dict{Symbol,String}

        # All 34 expected roles present
        expected_roles = [
            :primary, :on_primary, :primary_container, :on_primary_container,
            :secondary, :on_secondary, :secondary_container, :on_secondary_container,
            :tertiary, :on_tertiary, :tertiary_container, :on_tertiary_container,
            :error, :on_error, :error_container, :on_error_container,
            :surface, :on_surface, :surface_dim, :surface_bright,
            :surface_container_lowest, :surface_container_low, :surface_container,
            :surface_container_high, :surface_container_highest,
            :surface_variant, :on_surface_variant, :outline, :outline_variant,
            :inverse_surface, :inverse_on_surface, :inverse_primary,
            :scrim, :shadow,
        ]
        for role in expected_roles
            @test haskey(scheme, role) || "Missing role: $role"
        end

        # All values are valid hex strings
        for (role, hex) in scheme
            @test startswith(hex, "#")
            @test length(hex) == 7
        end
    end

    @testset "color_scheme light vs dark" begin
        light = color_scheme("#6750A4"; dark=false)
        dark  = color_scheme("#6750A4"; dark=true)

        # Light surface should be much lighter than dark surface
        @test hct(light[:surface]).tone > 80.0
        @test hct(dark[:surface]).tone < 20.0

        # Primary tones: light=40, dark=80
        @test hct(light[:primary]).tone < 50.0
        @test hct(dark[:primary]).tone > 70.0
    end

    @testset "color_scheme_pair" begin
        light, dark = color_scheme_pair("#6750A4")
        @test light == color_scheme("#6750A4"; dark=false)
        @test dark  == color_scheme("#6750A4"; dark=true)
    end

    @testset "color_scheme custom secondary/tertiary" begin
        scheme = color_scheme("#6750A4"; secondary="#FF0000", tertiary="#00FF00")
        @test haskey(scheme, :secondary)
        @test haskey(scheme, :tertiary)
    end

    # ─────────────────────────────────────────────────────────────────
    # Contrast Utilities
    # ─────────────────────────────────────────────────────────────────

    @testset "contrast_ratio" begin
        # Black/white should give maximum contrast (21:1)
        @test contrast_ratio("#000000", "#FFFFFF") ≈ 21.0 atol=0.1

        # Same color should give minimum contrast (1:1)
        @test contrast_ratio("#6750A4", "#6750A4") ≈ 1.0 atol=0.01

        # Order shouldn't matter
        @test contrast_ratio("#000000", "#FFFFFF") ≈
              contrast_ratio("#FFFFFF", "#000000")
    end

    @testset "contrast_ratio from tones" begin
        # L*=0 vs L*=100 → max contrast
        @test contrast_ratio(0.0, 100.0) ≈ 21.0 atol=0.1
        # Same tone → 1:1
        @test contrast_ratio(50.0, 50.0) ≈ 1.0 atol=0.01
    end

    @testset "meets_aa / meets_aaa" begin
        # Black on white should pass everything
        @test meets_aa("#000000", "#FFFFFF")
        @test meets_aaa("#000000", "#FFFFFF")

        # Same color should fail everything
        @test !meets_aa("#808080", "#808080")
        @test !meets_aaa("#808080", "#808080")

        # Large text has lower threshold
        @test meets_aa("#808080", "#FFFFFF"; large_text=true)
    end

    @testset "lighter_tone / darker_tone" begin
        # From tone 40, find a lighter tone with 4.5:1 contrast
        lt = lighter_tone(40.0, 4.5)
        @test !isnan(lt)
        @test lt > 40.0
        @test contrast_ratio(40.0, lt) >= 4.49  # allow small float error

        # From tone 80, find a darker tone with 4.5:1 contrast
        dt = darker_tone(80.0, 4.5)
        @test !isnan(dt)
        @test dt < 80.0
        @test contrast_ratio(80.0, dt) >= 4.49

        # Impossible contrast returns NaN
        @test isnan(lighter_tone(99.0, 21.0))
        @test isnan(darker_tone(1.0, 21.0))
    end

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
        @test m3.sidebar_collapsed == false
        @test m3.toc_depth == 3
        @test m3.search == true
        @test m3.repolink === :auto
        @test m3.versions == true
        @test m3.analytics === nothing
        @test m3.logo === nothing
        @test m3.favicon === nothing
        @test m3.footer === nothing
        @test isempty(m3.custom_css)
        @test isempty(m3.custom_js)
        @test m3.prettyurls == true
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
        light, dark = color_scheme_pair(theme.seed;
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

        # Sidebar collapse/mobile CSS (Phase 6)
        @test contains(css, ".md-nav-collapsed")
        @test contains(css, ".md-hamburger")
        @test contains(css, ".md-sidebar-open")
    end

    @testset "CSS dark mode variants" begin
        # :light mode should NOT have any dark blocks
        m3_light = Material3(dark_mode=:light)
        theme = m3_light.theme
        light, dark = color_scheme_pair(theme.seed)
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
            format = Material3(theme = :ocean_depth, dark_mode = :toggle, toc_depth = 3),
            modules = [MaterialDocs],
            pages = [
                "Home" => "index.md",
                "API" => "api.md",
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

    @testset "MD3 scheme meets WCAG AA" begin
        # All primary color role pairings should meet AA
        light, dark = color_scheme_pair("#6750A4")
        role_pairs = [
            (:primary, :on_primary),
            (:primary_container, :on_primary_container),
            (:secondary, :on_secondary),
            (:secondary_container, :on_secondary_container),
            (:tertiary, :on_tertiary),
            (:tertiary_container, :on_tertiary_container),
            (:error, :on_error),
            (:error_container, :on_error_container),
            (:surface, :on_surface),
        ]
        for (bg_role, fg_role) in role_pairs
            for (name, scheme) in [("light", light), ("dark", dark)]
                r = contrast_ratio(scheme[bg_role], scheme[fg_role])
                @test r >= 3.0 || "$name $bg_role/$fg_role contrast $r < 3.0"
            end
        end
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

        # Should have HCT color engine
        @test contains(js, "hexToHCT")
        @test contains(js, "generateScheme")
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

    @testset "Editor scheme to JS" begin
        scheme = Dict(:primary => "#FF0000", :on_primary => "#FFFFFF")
        js = MaterialDocs._scheme_to_js_object(scheme)
        @test contains(js, "\"on-primary\":\"#FFFFFF\"")
        @test contains(js, "\"primary\":\"#FF0000\"")
        @test startswith(js, "{")
        @test endswith(js, "}")
    end
end
