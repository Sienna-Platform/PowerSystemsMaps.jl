# Backend-agnostic data layer: normalize a value source into a per-item time series, and
# resolve component names to projected geographic coordinates. The result structs hold only
# plain numbers, so any rendering backend can draw them.

"""
Per-item time series. `values[i, j]` is the value of `names[i]` at `times[j]`; entries with
no data are `NaN`.
"""
struct TimeSeriesValues
    names::Vector{String}
    times::Vector{Dates.DateTime}
    values::Matrix{Float64}
end

_take_last(_, b) = b

function _wide_to_long(wide::DataFrames.DataFrame)
    long = DataFrames.stack(
        wide,
        DataFrames.Not(:DateTime);
        variable_name = :name,
        value_name = :value,
    )
    long.name = string.(long.name)
    return long
end

function _long_to_tsv(long::DataFrames.DataFrame, reducer::Function)
    names = unique(string.(long.name))
    times = sort(unique(long.DateTime))
    name_ix = Dict(n => i for (i, n) in enumerate(names))
    time_ix = Dict(t => j for (j, t) in enumerate(times))
    values = fill(NaN, length(names), length(times))
    seen = falses(length(names), length(times))
    for row in DataFrames.eachrow(long)
        i = name_ix[string(row.name)]
        j = time_ix[row.DateTime]
        v = Float64(row.value)
        values[i, j] = seen[i, j] ? reducer(values[i, j], v) : v
        seen[i, j] = true
    end
    return TimeSeriesValues(names, times, values)
end

"""
Normalize a value source to [`TimeSeriesValues`](@ref). Accepts a long `DataFrame`
(`:DateTime`, `:name`, `:value`), a wide `DataFrame` (`:DateTime` plus one column per item),
or a PowerAnalytics `PowerData`. `reducer(a, b)` combines duplicate `(name, time)` entries
(default keeps the last; pass `_max_abs` for duals).
"""
function time_series_values(df::DataFrames.DataFrame; reducer::Function = _take_last)
    cols = propertynames(df)
    if :name in cols && :value in cols && :DateTime in cols
        return _long_to_tsv(df, reducer)
    end
    return _long_to_tsv(_wide_to_long(df), reducer)
end

function time_series_values(pd::PA.PowerData; reducer::Function = _take_last)
    long = DataFrames.DataFrame(;
        DateTime = Dates.DateTime[],
        name = String[],
        value = Float64[],
    )
    for wide in values(pd.data)
        isempty(wide) && continue
        long = vcat(long, _wide_to_long(wide))
    end
    return _long_to_tsv(long, reducer)
end

# ---- geographic resolution ---------------------------------------------------------------

const _ARC_NAME_RE = r"^bus-(\d+)-bus-(\d+)"

struct EdgeGeometry
    names::Vector{String}
    from::Vector{Tuple{Float64, Float64}}   # projected (x, y)
    to::Vector{Tuple{Float64, Float64}}
    rating::Vector{Float64}
end

struct NodeGeometry
    names::Vector{String}
    point::Vector{Tuple{Float64, Float64}}  # projected (x, y)
end

function _bus_coord_maps(sys::PSY.System)
    by_name = Dict{String, Tuple{Float64, Float64}}()
    by_number = Dict{Int, Tuple{Float64, Float64}}()
    kv_by_number = Dict{Int, Float64}()
    for b in PSY.get_components(PSY.ACBus, sys)
        kv_by_number[PSY.get_number(b)] = Float64(PSY.get_base_voltage(b))
        has_coordinates(b) || continue
        lonlat = get_lonlat(b)
        by_name[PSY.get_name(b)] = lonlat
        by_number[PSY.get_number(b)] = lonlat
    end
    return (by_name = by_name, by_number = by_number, kv_by_number = kv_by_number)
end

function _branch_index(sys::PSY.System)
    index = Dict{String, NamedTuple{(:from, :to, :rating), Tuple{Int, Int, Float64}}}()
    for l in PSY.get_components(PSY.ACBranch, sys)
        arc = PSY.get_arc(l)
        index[PSY.get_name(l)] = (
            from = PSY.get_number(PSY.get_from(arc)),
            to = PSY.get_number(PSY.get_to(arc)),
            rating = _branch_rating(l),
        )
    end
    return index
end

function _branch_rating(branch::PSY.ACBranch)
    return Float64(PSY.get_rating(branch))
end

# Resolve a series name to a (from_number, to_number, rating). Prefers a real branch
# component; falls back to parsing `bus-<from>-bus-<to>` so merged double-circuit dual
# series (which have no single component) are still mappable.
function _resolve_arc(name::AbstractString, branch_index)
    if haskey(branch_index, name)
        e = branch_index[name]
        return (true, e.from, e.to, e.rating)
    end
    m = match(_ARC_NAME_RE, name)
    isnothing(m) && return (false, 0, 0, 0.0)
    return (true, parse(Int, m[1]), parse(Int, m[2]), 0.0)
end

"""
Build edge geometry for the items in `tsv`, projecting endpoints with `projection` and
keeping only branches whose from-bus base voltage is at least `min_base_voltage`. Returns
the geometry plus the row indices of `tsv` that resolved, so values stay aligned.
"""
function resolve_edges(
    sys::PSY.System,
    tsv::TimeSeriesValues;
    projection = lonlat_to_webmercator,
    min_base_voltage = 0.0,
)
    coords = _bus_coord_maps(sys)
    branch_index = _branch_index(sys)
    names = String[]
    from = Tuple{Float64, Float64}[]
    to = Tuple{Float64, Float64}[]
    rating = Float64[]
    kept = Int[]
    skipped = 0
    for (i, name) in enumerate(tsv.names)
        (ok, a, b, r) = _resolve_arc(name, branch_index)
        if !ok || !haskey(coords.by_number, a) || !haskey(coords.by_number, b)
            skipped += 1
            continue
        end
        get(coords.kv_by_number, a, 0.0) >= min_base_voltage || continue
        push!(names, name)
        push!(from, projection(coords.by_number[a]...))
        push!(to, projection(coords.by_number[b]...))
        push!(rating, r)
        push!(kept, i)
    end
    skipped > 0 &&
        @warn "Skipped $skipped series with no resolvable geographic endpoints"
    return (EdgeGeometry(names, from, to, rating), kept)
end

"""
Build node geometry for the items in `tsv`, matching each name to a bus by name or number
and projecting with `projection`. Returns the geometry plus the row indices of `tsv` that
resolved.
"""
function resolve_nodes(
    sys::PSY.System,
    tsv::TimeSeriesValues;
    projection = lonlat_to_webmercator,
)
    coords = _bus_coord_maps(sys)
    names = String[]
    point = Tuple{Float64, Float64}[]
    kept = Int[]
    skipped = 0
    for (i, name) in enumerate(tsv.names)
        (ok, lonlat) = _node_lonlat(name, coords)
        if !ok
            skipped += 1
            continue
        end
        push!(names, name)
        push!(point, projection(lonlat...))
        push!(kept, i)
    end
    skipped > 0 && @warn "Skipped $skipped series with no resolvable bus location"
    return (NodeGeometry(names, point), kept)
end

function _node_lonlat(name::AbstractString, coords)
    haskey(coords.by_name, name) && return (true, coords.by_name[name])
    n = tryparse(Int, name)
    (!isnothing(n) && haskey(coords.by_number, n)) && return (true, coords.by_number[n])
    return (false, (0.0, 0.0))
end
