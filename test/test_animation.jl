
# Exercise the generic animation engine + CairoMakie `record` with a synthetic value
# source, so no PowerSimulations solve is needed. The results -> get_branch_data path is
# covered by PowerAnalytics' own test suite.

sys = make_test_sys()

function coord_branch_names(system, n)
    out = String[]
    for l in PSY.get_components(PSY.ACBranch, system)
        arc = PSY.get_arc(l)
        if has_coordinates(PSY.get_from(arc)) && has_coordinates(PSY.get_to(arc))
            push!(out, PSY.get_name(l))
        end
        length(out) >= n && break
    end
    return out
end

function long_values(names, times)
    df = DataFrames.DataFrame(;
        DateTime = Dates.DateTime[],
        name = String[],
        value = Float64[],
    )
    for (k, nm) in enumerate(names), (j, t) in enumerate(times)
        push!(df, (t, nm, 10.0 * k + j))
    end
    return df
end

@testset "edge animation (synthetic)" begin
    names = coord_branch_names(sys, 15)
    @test !isempty(names)
    times = [Dates.DateTime(2024, 1, 1) + Dates.Hour(h) for h in 0:2]
    df = long_values(names, times)

    gifpath = joinpath(mktempdir(), "test_edges.gif")
    out = animate_map(
        sys, df;
        on = :edges, file = gifpath, framerate = 1, clim = (0.0, 200.0),
        backend = PSM.CairoMakieBackend(),
    )
    @test out == gifpath
    @test isfile(gifpath)
    @test filesize(gifpath) > 0
end

@testset "node animation (synthetic)" begin
    busnames = String[]
    for b in PSY.get_components(PSY.ACBus, sys)
        has_coordinates(b) && push!(busnames, PSY.get_name(b))
        length(busnames) >= 8 && break
    end
    @test !isempty(busnames)
    times = [Dates.DateTime(2024, 1, 1) + Dates.Hour(h) for h in 0:2]
    df = long_values(busnames, times)

    gifpath = joinpath(mktempdir(), "test_nodes.gif")
    out = animate_map(
        sys, df;
        on = :nodes, file = gifpath, framerate = 1,
        backend = PSM.CairoMakieBackend(),
    )
    @test out == gifpath
    @test isfile(gifpath)
    @test filesize(gifpath) > 0
end

@testset "value-source normalization" begin
    times = [Dates.DateTime(2024, 1, 1) + Dates.Hour(h) for h in 0:1]
    df = long_values(["a", "b"], times)
    tsv = time_series_values(df)
    @test Set(tsv.names) == Set(["a", "b"])
    @test length(tsv.times) == 2
    @test size(tsv.values) == (2, 2)
end
