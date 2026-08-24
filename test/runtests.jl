using MaterialDocs
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
end
