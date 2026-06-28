# Public plotting API. Core builds backend-agnostic render specs (plain projected numbers);
# the loaded backend extension implements the rendering stubs below.

# ---- render specs ------------------------------------------------------------------------

struct StaticMap
    node_x::Vector{Float64}
    node_y::Vector{Float64}
    node_color::Vector{<:Colors.Colorant}
    node_alpha::Vector{Float64}
    node_group::Vector{String}
    node_label::Vector{String}
    node_size::Float64
    edges::Vector{NTuple{4, Float64}}    # (x1, y1, x2, y2), projected
    rings::Vector{Vector{Tuple{Float64, Float64}}}  # projected
end

struct EdgeAnimationSpec
    geometry::EdgeGeometry               # projected endpoints
    times::Vector{Dates.DateTime}
    values::Matrix{Float64}              # [edge, time], transformed
    clim::Tuple{Float64, Float64}
    colormap::Symbol
    rings::Vector{Vector{Tuple{Float64, Float64}}}
    label::String
    title::Function                      # t -> String
    framerate::Int
    linewidth::Float64
    file::String
end

struct NodeAnimationSpec
    geometry::NodeGeometry
    times::Vector{Dates.DateTime}
    values::Matrix{Float64}
    clim::Tuple{Float64, Float64}
    colormap::Symbol
    rings::Vector{Vector{Tuple{Float64, Float64}}}
    label::String
    title::Function
    framerate::Int
    markersize::Float64
    file::String
end

# ---- backend stubs (methods provided by extensions) --------------------------------------

_render_static(::PlottingBackend, ::StaticMap; kwargs...) = _no_backend_loaded()
_render_edge_animation(::PlottingBackend, ::EdgeAnimationSpec) = _no_backend_loaded()
_render_node_animation(::PlottingBackend, ::NodeAnimationSpec) = _no_backend_loaded()

# ---- helpers -----------------------------------------------------------------------------

_title_fn(title::Function) = title
_title_fn(title::AbstractString) = t -> "$title — $t"
_title_fn(::Nothing) = t -> string(t)

function _auto_clim(values)
    finite = filter(isfinite, values)
    isempty(finite) && return (0.0, 1.0)
    lo, hi = extrema(finite)
    lo == hi && return (lo, lo + 1.0)
    return (Float64(lo), Float64(hi))
end

_identity_transform(value, _meta) = value

function _resolve_clim(::Nothing, values)
    return _auto_clim(values)
end

function _resolve_clim(clim, _values)
    return Tuple{Float64, Float64}(clim)
end

function _projected_rings(shapefile, projection, filter_column, filter_value)
    isnothing(shapefile) && return Vector{Vector{Tuple{Float64, Float64}}}()
    rings = shapefile_rings(
        shapefile;
        filter_column = filter_column,
        filter_value = filter_value,
    )
    return [[projection(lon, lat) for (lon, lat) in ring] for ring in rings]
end

# ---- static maps -------------------------------------------------------------------------

"""
Render a static map of a `make_graph` result, projecting node positions with `projection`.
Pass `rings` (projected) to draw a basemap underneath. Requires a loaded backend.
"""
function plot_graph(
    g::MetaGraph;
    backend::PlottingBackend = default_backend(),
    projection = lonlat_to_webmercator,
    rings = Vector{Vector{Tuple{Float64, Float64}}}(),
    nodesize = 3.0,
    kwargs...,
)
    x = get_prop(g, :x)
    y = get_prop(g, :y)
    projected = [projection(xi, yi) for (xi, yi) in zip(x, y)]
    node_x = first.(projected)
    node_y = last.(projected)
    edge_segments = NTuple{4, Float64}[]
    for e in edges(g)
        push!(
            edge_segments,
            (node_x[e.src], node_y[e.src], node_x[e.dst], node_y[e.dst]),
        )
    end
    m = StaticMap(
        node_x,
        node_y,
        get_prop(g, :nodecolor),
        Float64.(get_prop(g, :alpha)),
        string.(get_prop(g, :group)),
        string.(get_prop(g, :name)),
        Float64(nodesize),
        edge_segments,
        rings,
    )
    return _render_static(backend, m; kwargs...)
end

"""
Build a graph from `sys` and render it as a static geographic map over the polygons in
`shapefile`. `color_by`, `filter_column`/`filter_value`, and `projection` are forwarded to
graph construction and basemap extraction.
"""
function plot_map(
    sys::PSY.System,
    shapefile::AbstractString;
    backend::PlottingBackend = default_backend(),
    projection = lonlat_to_webmercator,
    color_by = nothing,
    filter_column = nothing,
    filter_value = nothing,
    kwargs...,
)
    g = make_graph(sys; color_by = color_by, kwargs...)
    rings = _projected_rings(shapefile, projection, filter_column, filter_value)
    return plot_graph(
        g;
        backend = backend,
        projection = projection,
        rings = rings,
        kwargs...,
    )
end

# ---- animation ---------------------------------------------------------------------------

function _transformed_edge_values(
    geometry::EdgeGeometry,
    tsv::TimeSeriesValues,
    kept,
    transform,
)
    values = tsv.values[kept, :]
    out = similar(values)
    for i in axes(values, 1)
        meta = (name = geometry.names[i], rating = geometry.rating[i])
        for j in axes(values, 2)
            out[i, j] = transform(values[i, j], meta)
        end
    end
    return out
end

function _transformed_node_values(
    geometry::NodeGeometry,
    tsv::TimeSeriesValues,
    kept,
    transform,
)
    values = tsv.values[kept, :]
    out = similar(values)
    for i in axes(values, 1)
        meta = (name = geometry.names[i],)
        for j in axes(values, 2)
            out[i, j] = transform(values[i, j], meta)
        end
    end
    return out
end

"""
    animate_map(sys, data; kwargs...)

Animate a geographic map of `sys`, coloring each item by a user-supplied quantity over the
realized timeline, and write an animation file (`.gif` or `.mp4`). This is the generic
entry point: `data` is whatever variable you want to map.

`data` is any value source accepted by [`time_series_values`](@ref): a long `DataFrame`
(`:DateTime`, `:name`, `:value`, e.g. from `PowerSimulations.read_realized_dual`), a wide
`DataFrame`, or a PowerAnalytics `PowerData` (e.g. from `get_branch_data` /
`get_generation_data`). A branch dual is just another such output — read it and pass it in.

# Keyword arguments
 - `on::Symbol = :edges` : `:edges` colors branches, `:nodes` colors buses.
 - `transform = (value, meta) -> value` : per-value transform; `meta` is `(; name, rating)`
   for edges and `(; name)` for nodes (e.g. `(v, m) -> 100 * abs(v) / m.rating` for loading%).
 - `reducer` : combines duplicate `(name, time)` entries (default keeps the last; matters only
   when a name appears in more than one container, e.g. two-sided constraint duals).
 - `clim` : fixed color range; computed from the data when `nothing`.
 - `colormap::Symbol = :turbo`, `label::String = ""`, `title = nothing` (String or `t -> String`).
 - `projection = lonlat_to_webmercator`, `min_base_voltage = 0.0` (edges only).
 - `shapefile`, `filter_column`, `filter_value` : optional basemap.
 - `framerate::Int = 2`, `linewidth`/`markersize`, `file::String = "map.gif"`.
 - `backend::PlottingBackend = default_backend()`.
"""
function animate_map(
    sys::PSY.System,
    data;
    on::Symbol = :edges,
    transform::Function = _identity_transform,
    reducer::Function = _take_last,
    clim = nothing,
    colormap::Symbol = :turbo,
    label::AbstractString = "",
    title = nothing,
    projection = lonlat_to_webmercator,
    min_base_voltage = 0.0,
    shapefile = nothing,
    filter_column = nothing,
    filter_value = nothing,
    framerate::Int = 2,
    linewidth = 2.0,
    markersize = 6.0,
    file::AbstractString = "map.gif",
    backend::PlottingBackend = default_backend(),
)
    tsv = time_series_values(data; reducer = reducer)
    rings = _projected_rings(shapefile, projection, filter_column, filter_value)
    title_fn = _title_fn(title)
    if on === :edges
        (geometry, kept) =
            resolve_edges(
                sys,
                tsv;
                projection = projection,
                min_base_voltage = min_base_voltage,
            )
        isempty(geometry.names) &&
            (@warn "No mappable edges; nothing to animate"; return nothing)
        values = _transformed_edge_values(geometry, tsv, kept, transform)
        range = _resolve_clim(clim, values)
        spec = EdgeAnimationSpec(
            geometry, tsv.times, values, range, colormap, rings, String(label),
            title_fn, framerate, Float64(linewidth), String(file),
        )
        return _render_edge_animation(backend, spec)
    elseif on === :nodes
        (geometry, kept) = resolve_nodes(sys, tsv; projection = projection)
        isempty(geometry.names) &&
            (@warn "No mappable nodes; nothing to animate"; return nothing)
        values = _transformed_node_values(geometry, tsv, kept, transform)
        range = _resolve_clim(clim, values)
        spec = NodeAnimationSpec(
            geometry, tsv.times, values, range, colormap, rings, String(label),
            title_fn, framerate, Float64(markersize), String(file),
        )
        return _render_node_animation(backend, spec)
    end
    throw(ArgumentError("`on` must be :edges or :nodes, got $(repr(on))"))
end

# ---- convenience wrappers (thin sugar over animate_map) ----------------------------------

"""
Animate branch loading percent (`100 * |flow| / rating`) over the realized timeline. Reads
branch flows from `results` with PowerAnalytics. Lines with no positive rating are dropped.
"""
function animate_line_loading(
    sys::PSY.System,
    results;
    clim = (0.0, 120.0),
    label::AbstractString = "loading %",
    file::AbstractString = "map_line_loading.gif",
    kwargs...,
)
    data = PA.get_branch_data(results)
    return animate_map(
        sys, data;
        on = :edges, transform = _loading_pct, clim = clim, label = label, file = file,
        kwargs...,
    )
end

function _loading_pct(value, meta)
    if meta.rating > 0
        return 100 * abs(value) / meta.rating
    end
    return NaN
end

"""
Animate signed branch active power flow (MW) over the realized timeline.
"""
function animate_branch_flow(
    sys::PSY.System,
    results;
    colormap::Symbol = :balance,
    label::AbstractString = "flow (MW)",
    file::AbstractString = "map_branch_flow.gif",
    kwargs...,
)
    data = PA.get_branch_data(results)
    return animate_map(
        sys, data;
        on = :edges, colormap = colormap, label = label, file = file, kwargs...,
    )
end

# To animate any other branch output (e.g. a flow-constraint dual / congestion price),
# read it like any realized variable and pass it to `animate_map` directly:
#
#     duals = PowerSimulations.read_realized_dual(results, "FlowRateConstraint__Line")
#     animate_map(sys, duals; on = :edges, transform = (v, _) -> abs(v),
#                 label = "|dual| (\$/MWh)")
#
# Series named `bus-<from>-bus-<to>__…` (merged double-circuit equivalents with no single
# branch component) are mapped by parsing their endpoints, so duals on those still render.
