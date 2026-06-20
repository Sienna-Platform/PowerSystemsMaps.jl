# PowerSystemsMaps.jl
[![main - CI](https://github.com/Sienna-Platform/PowerSystemsMaps.jl/actions/workflows/main-tests.yml/badge.svg)](https://github.com/Sienna-Platform/PowerSystemsMaps.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/Sienna-Platform/PowerSystemsMaps.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sienna-Platform/PowerSystemsMaps.jl)
[<img src="https://img.shields.io/badge/slack-@SIIP/PG-blue.svg?logo=slack">](https://join.slack.com/t/core-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)

A (relatively) simple Julia module for plotting [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl) networks and making maps.

## Installation

```julia
using Pkg; Pkg.add("PowerSystemsMaps")
```

## Example

```julia
using PowerSystems
using PowerSystemsMaps
PSM = PowerSystemsMaps
PSM.Plots.plotlyjs() # load the PlotlyJS backend

sys = System("system.json")

# create a graph from the system
g = make_graph(sys, K = 0.01)

# load a shapefile
shp = PSM.Shapefile.shapes(PSM.Shapefile.Table("municipalities.shp"))
shp = PSM.lonlat_to_webmercator(shp) #adjust coordinates

# plot a map from shapefile
p = plot(
    shp,
    fillcolor = "grey",
    background_color = "white",
    linecolor = "darkgrey",
    axis = nothing,
    border = :none,
    label = "",
    legend_font_color = :red,
)

# plot the network on the map
p = plot_net!(
    p,
    g,
    nodesize = 3.0,
    linecolor = "blue",
    linewidth = 0.6,
    lines = true,
    #nodecolor = "red",
    nodealpha = 1.0,
    shownodelegend = true,
    size = (1500,800),
    buffer = 0.4e4
)

```
