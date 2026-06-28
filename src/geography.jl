# Bus geography, projections, and shapefile ring extraction. Backend-agnostic: produces
# plain coordinate data that any rendering backend can draw.

"""
Return `true` when `bus` carries a `GeographicInfo` supplemental attribute holding a GeoJSON
`Point`.
"""
function has_coordinates(bus::PSY.ACBus)
    for gi in PSY.get_supplemental_attributes(PSY.GeographicInfo, bus)
        if get(PSY.get_geo_json(gi), "type", "") == "Point"
            return true
        end
    end
    return false
end

"""
Return `(lon, lat)` for `bus` from its `GeographicInfo` GeoJSON `Point`. Guard calls with
[`has_coordinates`](@ref); this errors when no point is present rather than returning a
sentinel.
"""
function get_lonlat(bus::PSY.ACBus)
    for gi in PSY.get_supplemental_attributes(PSY.GeographicInfo, bus)
        geo = PSY.get_geo_json(gi)
        if get(geo, "type", "") == "Point"
            coords = geo["coordinates"]
            return (Float64(coords[1]), Float64(coords[2]))
        end
    end
    error(
        "ACBus $(PSY.get_name(bus)) has no GeographicInfo GeoJSON Point; " *
        "attach one with add_supplemental_attribute!(sys, bus, GeographicInfo(...)).",
    )
end

# A projection maps (lon, lat) -> (x, y). The default is Web Mercator, matching the
# convention used by common basemap tiles.
"""
Project a `(lon, lat)` pair (degrees) to Web Mercator meters.
"""
function lonlat_to_webmercator(lon, lat)
    abs(lon) > 180 && throw(ArgumentError("Maximum longitude is 180."))
    abs(lat) >= 85.051129 && throw(
        ArgumentError(
            "Web Mercator maximum latitude is 85.051129 (the latitude at which the full " *
            "map becomes a square).",
        ),
    )
    a = 6378137.0  # WGS84 equatorial radius (m)
    λ = lon * 0.017453292519943295
    ϕ = lat * 0.017453292519943295
    x = a * λ
    y = a * atanh(sin(ϕ))
    return (x, y)
end

lonlat_to_webmercator(lonlat::Tuple) = lonlat_to_webmercator(first(lonlat), last(lonlat))

"""
Return a local equirectangular projection centered at `lat0` (degrees). Longitudes are
scaled by `cos(lat0)` so that a `DataAspect` axis renders without east-west distortion.
"""
function equirectangular(lat0)
    k = cosd(lat0)
    return (lon, lat) -> (lon * k, lat)
end

_keep_mask(tbl, ::Nothing, ::Any) = trues(length(Shapefile.shapes(tbl)))

function _keep_mask(tbl, column, value)
    return getproperty(tbl, Symbol(column)) .== value
end

_push_rings!(rings, ::Missing) = rings

function _push_rings!(rings, poly::Shapefile.Polygon)
    pts = poly.points
    bounds = vcat(Int.(poly.parts) .+ 1, length(pts) + 1)  # 1-based ring starts + sentinel
    for r in 1:(length(bounds) - 1)
        push!(rings, [(p.x, p.y) for p in pts[bounds[r]:(bounds[r + 1] - 1)]])
    end
    return rings
end

"""
Read polygon rings (lists of `(lon, lat)` tuples) from a shapefile, optionally keeping only
rows where `filter_column == filter_value`. Each polygon contributes one ring per part
(mainland plus islands), so the result is a flat vector of rings suitable for drawing as a
basemap underneath a network.
"""
function shapefile_rings(
    path::AbstractString;
    filter_column = nothing,
    filter_value = nothing,
)
    tbl = Shapefile.Table(path)
    geoms = Shapefile.shapes(tbl)
    keep = _keep_mask(tbl, filter_column, filter_value)
    rings = Vector{Vector{Tuple{Float64, Float64}}}()
    for (i, g) in enumerate(geoms)
        keep[i] || continue
        _push_rings!(rings, g)
    end
    return rings
end
