module CairoMakieExt

using PowerSystemsMaps
using CairoMakie
import Colors

const PSM = PowerSystemsMaps

function _draw_rings!(ax, rings)
    isempty(rings) && return
    pts = CairoMakie.Point2f[]
    for ring in rings
        for (x, y) in ring
            push!(pts, CairoMakie.Point2f(x, y))
        end
        push!(pts, CairoMakie.Point2f(NaN, NaN))  # break between rings
    end
    CairoMakie.lines!(ax, pts; color = (:gray, 0.55), linewidth = 0.4)
    return
end

function _node_colors(m::PSM.StaticMap)
    return [Colors.alphacolor(c, a) for (c, a) in zip(m.node_color, m.node_alpha)]
end

function PowerSystemsMaps._render_static(
    ::PSM.CairoMakieBackend,
    m::PSM.StaticMap;
    size = (900, 1050),
    title = "",
    kwargs...,
)
    fig = CairoMakie.Figure(; size = size)
    ax = CairoMakie.Axis(fig[1, 1]; aspect = CairoMakie.DataAspect(), title = title)
    CairoMakie.hidedecorations!(ax)
    CairoMakie.hidespines!(ax)
    _draw_rings!(ax, m.rings)

    seg = CairoMakie.Point2f[]
    for (x1, y1, x2, y2) in m.edges
        push!(seg, CairoMakie.Point2f(x1, y1))
        push!(seg, CairoMakie.Point2f(x2, y2))
    end
    isempty(seg) ||
        CairoMakie.linesegments!(ax, seg; color = (:black, 0.3), linewidth = 0.6)

    CairoMakie.scatter!(
        ax, m.node_x, m.node_y;
        color = _node_colors(m), markersize = m.node_size + 4.0,
    )
    return fig
end

function _segment_points(g::PSM.EdgeGeometry)
    pts = CairoMakie.Point2f[]
    for i in eachindex(g.names)
        push!(pts, CairoMakie.Point2f(g.from[i]...))
        push!(pts, CairoMakie.Point2f(g.to[i]...))
    end
    return pts
end

function PowerSystemsMaps._render_edge_animation(
    ::PSM.CairoMakieBackend,
    spec::PSM.EdgeAnimationSpec,
)
    segpts = _segment_points(spec.geometry)
    fig = CairoMakie.Figure(; size = (900, 1050))
    ax = CairoMakie.Axis(
        fig[1, 1];
        aspect = CairoMakie.DataAspect(),
        title = spec.title(first(spec.times)),
    )
    CairoMakie.hidedecorations!(ax)
    CairoMakie.hidespines!(ax)
    _draw_rings!(ax, spec.rings)

    colorobs = CairoMakie.Observable(fill(Float64(spec.clim[1]), length(segpts)))
    CairoMakie.linesegments!(
        ax, segpts;
        color = colorobs, colormap = spec.colormap, colorrange = spec.clim,
        linewidth = spec.linewidth,
    )
    CairoMakie.Colorbar(
        fig[1, 2]; colormap = spec.colormap, colorrange = spec.clim, label = spec.label,
    )

    CairoMakie.record(
        fig,
        spec.file,
        eachindex(spec.times);
        framerate = spec.framerate,
    ) do ti
        vals = Float64[]
        for i in eachindex(spec.geometry.names)
            v = spec.values[i, ti]
            push!(vals, v)
            push!(vals, v)
        end
        colorobs[] = vals
        ax.title = spec.title(spec.times[ti])
    end
    return spec.file
end

function PowerSystemsMaps._render_node_animation(
    ::PSM.CairoMakieBackend,
    spec::PSM.NodeAnimationSpec,
)
    pts = [CairoMakie.Point2f(p...) for p in spec.geometry.point]
    fig = CairoMakie.Figure(; size = (900, 1050))
    ax = CairoMakie.Axis(
        fig[1, 1];
        aspect = CairoMakie.DataAspect(),
        title = spec.title(first(spec.times)),
    )
    CairoMakie.hidedecorations!(ax)
    CairoMakie.hidespines!(ax)
    _draw_rings!(ax, spec.rings)

    colorobs = CairoMakie.Observable(fill(Float64(spec.clim[1]), length(pts)))
    CairoMakie.scatter!(
        ax, pts;
        color = colorobs, colormap = spec.colormap, colorrange = spec.clim,
        markersize = spec.markersize,
    )
    CairoMakie.Colorbar(
        fig[1, 2]; colormap = spec.colormap, colorrange = spec.clim, label = spec.label,
    )

    CairoMakie.record(
        fig,
        spec.file,
        eachindex(spec.times);
        framerate = spec.framerate,
    ) do ti
        colorobs[] = Float64[spec.values[i, ti] for i in eachindex(spec.geometry.names)]
        ax.title = spec.title(spec.times[ti])
    end
    return spec.file
end

end # module CairoMakieExt
