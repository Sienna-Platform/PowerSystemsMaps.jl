module PowerSystemsMaps

# backend selection
export PlottingBackend, CairoMakieBackend, PlotlyLightBackend
export default_backend

# geography
export has_coordinates, get_lonlat, lonlat_to_webmercator, equirectangular, shapefile_rings

# graph + static maps
export make_graph, plot_graph, plot_map

# animation
export animate_map
export animate_line_loading, animate_branch_flow
export time_series_values

import Dates
import DataFrames
import Colors
import NetworkLayout
import Shapefile
import GeometryBasics
import PowerSystems
import PowerAnalytics

using Graphs
using MetaGraphsNext

const PSY = PowerSystems
const PA = PowerAnalytics

include("backends.jl")
include("geography.jl")
include("graph.jl")
include("mapdata.jl")
include("plots.jl")

function __init__()
    has_makie = haskey(Base.loaded_modules, _CAIROMAKIE_PKGID)
    has_plotly = haskey(Base.loaded_modules, _PLOTLYLIGHT_PKGID)
    if !(has_makie || has_plotly)
        @warn "PowerSystemsMaps: no plotting backend loaded. Run `using CairoMakie` or " *
              "`using PlotlyLight` before calling plotting functions."
    end
end

end # module PowerSystemsMaps
