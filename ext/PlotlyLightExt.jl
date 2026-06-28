module PlotlyLightExt

using PowerSystemsMaps
using PlotlyLight
import Colors

const PSM = PowerSystemsMaps

function _rgba_string(c, a)
    rgb = Colors.RGB(c)
    r = round(Int, 255 * Colors.red(rgb))
    g = round(Int, 255 * Colors.green(rgb))
    b = round(Int, 255 * Colors.blue(rgb))
    return "rgba($r,$g,$b,$a)"
end

function _ring_xy(rings)
    x = Float64[]
    y = Float64[]
    for ring in rings
        for (px, py) in ring
            push!(x, px)
            push!(y, py)
        end
        push!(x, NaN)
        push!(y, NaN)
    end
    return (x, y)
end

function _edge_xy(edges)
    x = Float64[]
    y = Float64[]
    for (x1, y1, x2, y2) in edges
        append!(x, (x1, x2, NaN))
        append!(y, (y1, y2, NaN))
    end
    return (x, y)
end

function _equal_aspect_layout()
    layout = PlotlyLight.Config()
    layout.yaxis.scaleanchor = "x"
    layout.yaxis.scaleratio = 1
    layout.xaxis.visible = false
    layout.yaxis.visible = false
    layout.showlegend = false
    return layout
end

function PowerSystemsMaps._render_static(
    ::PSM.PlotlyLightBackend,
    m::PSM.StaticMap;
    kwargs...,
)
    p = PlotlyLight.Plot(PlotlyLight.Config[], _equal_aspect_layout())

    if !isempty(m.rings)
        (rx, ry) = _ring_xy(m.rings)
        p(
            PlotlyLight.Config(;
                type = "scatter", x = rx, y = ry, mode = "lines",
                line = PlotlyLight.Config(; color = "rgba(128,128,128,0.55)", width = 0.4),
                hoverinfo = "skip", showlegend = false,
            ),
        )
    end
    if !isempty(m.edges)
        (ex, ey) = _edge_xy(m.edges)
        p(
            PlotlyLight.Config(;
                type = "scatter", x = ex, y = ey, mode = "lines",
                line = PlotlyLight.Config(; color = "rgba(0,0,0,0.3)", width = 0.6),
                hoverinfo = "skip", showlegend = false,
            ),
        )
    end
    colors = [_rgba_string(c, a) for (c, a) in zip(m.node_color, m.node_alpha)]
    p(
        PlotlyLight.Config(;
            type = "scatter", x = m.node_x, y = m.node_y, mode = "markers",
            marker = PlotlyLight.Config(; color = colors, size = m.node_size + 4.0),
            text = m.node_label, hoverinfo = "text", showlegend = false,
        ),
    )
    return p
end

function _animation_unsupported()
    throw(
        ErrorException(
            "The PlotlyLight backend does not support animation export (its Plot has no " *
            "frames). Use the CairoMakie backend for GIF/mp4 animations " *
            "(`using CairoMakie`), or call `plot_map`/`plot_graph` for an interactive " *
            "static PlotlyLight map.",
        ),
    )
end

PowerSystemsMaps._render_edge_animation(::PSM.PlotlyLightBackend, ::PSM.EdgeAnimationSpec) =
    _animation_unsupported()
PowerSystemsMaps._render_node_animation(::PSM.PlotlyLightBackend, ::PSM.NodeAnimationSpec) =
    _animation_unsupported()

end # module PlotlyLightExt
