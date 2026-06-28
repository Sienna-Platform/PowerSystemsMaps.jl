# Static network-topology graph built from a PowerSystems.System. Buses with geographic
# coordinates are pinned; the rest are laid out with SFDP. Backend-agnostic: stores node
# positions/colors as MetaGraph properties for a backend to render.

const PT = GeometryBasics.Point{2, Float64}

function set_prop!(g::MetaGraph, field::Symbol, data)
    for (ix, v) in enumerate(labels(g))
        g[v][field] = data[ix]
    end
    return
end

function get_prop(g::MetaGraph, field::Symbol)
    return [get(g[v], field, nothing) for v in labels(g)]
end

function _area_name(bus::PSY.ACBus)
    area = PSY.get_area(bus)
    return _area_name(area)
end

_area_name(area::PSY.Area) = PSY.get_name(area)
_area_name(::Nothing) = "unknown"

function color_nodes!(
    g,
    sys,
    node_colors::Vector{Pair{String, Colors.RGB{Colors.N0f8}}},
)
    for (ix, b) in enumerate(PSY.get_components(PSY.ACBus, sys))
        alpha = has_coordinates(b) ? 1.0 : 0.1
        g[PSY.get_name(b)][:nodecolor] = last(node_colors[ix])
        g[PSY.get_name(b)][:alpha] = alpha
        g[PSY.get_name(b)][:group] = first(node_colors[ix])
    end
    return
end

function color_nodes!(g, sys, color_by::Type{T}) where {T <: PSY.AggregationTopology}
    accessor = PSY.get_aggregation_topology_accessor(color_by)
    agg_top = PSY.get_components(color_by, sys)
    buses = PSY.get_components(PSY.ACBus, sys)
    area_colors = Dict(
        zip(
            PSY.get_name.(agg_top),
            Colors.distinguishable_colors(length(agg_top), Colors.colorant"blue"),
        ),
    )
    node_colors = [
        PSY.get_name(accessor(n)) => area_colors[PSY.get_name(accessor(n))] for n in buses
    ]
    color_nodes!(g, sys, node_colors)
    return
end

# Generic accessor: `color_by(bus)` returns a groupable value (e.g. a fuel string or area
# name). Nodes are colored by distinguishable colors over the unique accessor values.
function color_nodes!(g, sys, color_by::Function)
    buses = PSY.get_components(PSY.ACBus, sys)
    colorvals = string.(color_by.(buses))
    field_colors = Dict(
        zip(
            unique(colorvals),
            Colors.distinguishable_colors(length(unique(colorvals)), Colors.colorant"blue"),
        ),
    )
    node_colors = [v => field_colors[v] for v in colorvals]
    color_nodes!(g, sys, node_colors)
    return
end

color_nodes!(g, sys, ::Nothing) = color_nodes!(g, sys, _area_name)

"""
Construct a `MetaGraph` from a `PowerSystems.System`.

Accepted kwargs:
 - `K::Float64` : spring force constant for the SFDP layout
 - `color_by` : `nothing` (color by area), an `AggregationTopology` type, or a `bus -> value`
   accessor function
 - `name_accessor::Function` : function to access bus display names
"""
function make_graph(sys::PSY.System; kwargs...)
    @info "creating graph from System"
    g = MetaGraph(
        Graph();
        label_type = String,
        vertex_data_type = Dict{Symbol, Any},
        edge_data_type = Vector{<:PSY.Branch},
        graph_data = "data",
    )

    for b in PSY.get_components(PSY.ACBus, sys)
        data = Dict{Symbol, Any}(
            :name => PSY.get_name(b),
            :number => PSY.get_number(b),
            :area => _area_name(b),
        )
        if has_coordinates(b)
            (lon, lat) = get_lonlat(b)
            data[:initial_position] = PT(lon, lat)
        end
        g[PSY.get_name(b)] = data
    end
    for a in PSY.get_components(PSY.Arc, sys)
        fr = PSY.get_from(a)
        to = PSY.get_to(a)
        g[PSY.get_name.([fr, to])...] =
            collect(PSY.get_components(x -> PSY.get_arc(x) == a, PSY.Branch, sys))
    end

    color_by = get(kwargs, :color_by, nothing)
    color_nodes!(g, sys, color_by)

    a = adjacency_matrix(g)
    ip = Dict(zip(1:nv(g), get_prop(g, :initial_position)))
    filter!(p -> !isnothing(last(p)), ip)

    if length(ip) != nv(g)
        @info "calculating node locations with SFDP"
        network = NetworkLayout.sfdp(
            a;
            tol = get(kwargs, :tol, 1.0),
            C = get(kwargs, :C, 0.0002),
            K = get(kwargs, :K, 0.1),
            iterations = get(kwargs, :iterations, 100),
            pin = ip,
        )
    else
        network = [ip[k] for k in 1:nv(g)]
    end

    set_prop!(g, :x, first.(network))
    set_prop!(g, :y, last.(network))
    name_accessor = get(kwargs, :name_accessor, PSY.get_name)
    set_prop!(g, :name, name_accessor.(PSY.get_components(PSY.ACBus, sys)))

    return g
end
