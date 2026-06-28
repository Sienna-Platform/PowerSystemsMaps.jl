
sys = make_test_sys()
@testset "graph + static map" begin
    g = make_graph(sys; K = 0.01)
    @test typeof(g) <: PSM.MetaGraphsNext.MetaGraph
    @test length(PSM.get_prop(g, :x)) == 200

    shapefile = joinpath(TEST_DIR, "test_data", "IL_BNDY_County", "IL_BNDY_County_Py.shp")
    rings = PSM.shapefile_rings(shapefile)
    @test !isempty(rings)
    @test eltype(first(rings)) == Tuple{Float64, Float64}

    # Static map over the county basemap, rendered with the CairoMakie backend.
    fig = plot_map(
        sys,
        shapefile;
        backend = PSM.CairoMakieBackend(),
        nodesize = 3.0,
    )
    @test fig isa CairoMakie.Figure

    # plot_graph alone (no basemap) should also render.
    fig2 = plot_graph(g; backend = PSM.CairoMakieBackend())
    @test fig2 isa CairoMakie.Figure
end
