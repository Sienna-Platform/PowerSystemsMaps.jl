# PowerSystemsMaps.jl
[![main - CI](https://github.com/Sienna-Platform/PowerSystemsMaps.jl/actions/workflows/main-tests.yml/badge.svg)](https://github.com/Sienna-Platform/PowerSystemsMaps.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/Sienna-Platform/PowerSystemsMaps.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sienna-Platform/PowerSystemsMaps.jl)
[<img src="https://img.shields.io/badge/slack-@SIIP/PG-blue.svg?logo=slack">](https://join.slack.com/t/core-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)

A Julia module for plotting [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl)
networks on maps, including animated GIFs/MP4s of a quantity (line loading, flow, duals, ...)
over a simulation timeline.

Rendering is provided by selectable backends, mirroring
[PowerGraphics.jl](https://github.com/Sienna-Platform/PowerGraphics.jl): load **CairoMakie**
(for static maps and GIF/MP4 animation) or **PlotlyLight** (for interactive static maps)
before calling any plotting function.

## Installation

```julia
using Pkg; Pkg.add("PowerSystemsMaps")
```

## Static map

```julia
using PowerSystems
using CairoMakie          # selectable backend; load before plotting
using PowerSystemsMaps

sys = System("system.json")

# build a graph from the system (geographic buses are pinned, others laid out with SFDP)
g = make_graph(sys; K = 0.01)

# plot the network over a shapefile basemap
fig = plot_map(sys, "counties.shp"; color_by = nothing, nodesize = 3.0)
```

## Animated map (the variable is yours to choose)

`animate_map` is generic: pass any value source (a long `DataFrame` with `:DateTime`,
`:name`, `:value`, a wide `DataFrame`, or a [PowerAnalytics](https://github.com/Sienna-Platform/PowerAnalytics.jl)
`PowerData`) and it colors each branch (or bus) by that quantity across the realized
timeline.

```julia
using PowerSimulations, PowerAnalytics, CairoMakie, PowerSystemsMaps

results = get_decision_problem_results(SimulationResults(path), "UC")

# branch flows pulled via PowerAnalytics.get_branch_data, colored as loading %
animate_line_loading(sys, results; shapefile = "counties.shp", file = "loading.gif")

# or map any variable yourself
data = PowerAnalytics.get_branch_data(results)
animate_map(sys, data; on = :edges, label = "flow (MW)", file = "flow.gif")

# a dual is just another branch output — read it and pass it in
duals = PowerSimulations.read_realized_dual(results, "FlowRateConstraint__Line")
animate_map(sys, duals; on = :edges, transform = (v, _) -> abs(v), label = "|dual| (\$/MWh)")
```

Convenience wrappers: `animate_line_loading`, `animate_branch_flow`.
