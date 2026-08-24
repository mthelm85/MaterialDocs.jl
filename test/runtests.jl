using MaterialDocs
using Test
using Aqua
using JET

@testset "MaterialDocs.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(MaterialDocs)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(MaterialDocs; target_defined_modules = true)
    end
    # Write your tests here.
end
