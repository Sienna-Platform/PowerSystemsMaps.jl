# PowerSystemsMaps.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Purpose & place in the stack

PowerSystemsMaps (PSM) is a small **leaf visualization package**. It consumes a PowerSystems.jl `System` and draws the network — optionally on top of a geographic basemap from a shapefile. It is the bottom of the dependency chain: nothing else in Sienna depends on it, and it is *not* a JuMP/optimization package.

Verified `[deps]` (Project.toml, `version = 0.2.2`): `PowerSystems` (compat `4`), `Plots` (`1`), `Graphs` (`1.11`), `MetaGraphsNext` (`0.7`), `NetworkLayout` (`0.4`), `Shapefile` (`0.11, 0.12, 0.13`), `GeometryBasics` (`0.4`), `Colors` (`0.12`). Julia `^1.6`.

## Architecture: System → graph → layout → plot

Only two source files:

- `src/PowerSystemsMaps.jl` — module file: `using`/`import` lines and the export list. Exports: `plot`, `plot!`, `plot_net`, `plot_net!`, `plot_components!`, `make_graph`, `plot_map`. (`plot`/`plot!` are re-exported from Plots.) `include`s the one implementation file.
- `src/plot_network.jl` — all the logic.

Pipeline inside `make_graph`:
1. Build a `MetaGraphsNext.MetaGraph` (`String` labels, `Dict{Symbol,Any}` vertex data) from the `System` — one vertex per `Bus`, edges from `Arc`s carrying the `Branch` components.
2. Bus geo-coordinates come from `GeographicInfo` supplemental attributes (GeoJSON `Point`); buses without one fall back to `DEFAULT_LON`/`DEFAULT_LAT`.
3. Color nodes (`color_nodes!`, dispatched on `color_by`: a `Symbol` field, an `AggregationTopology` subtype, or default `:area`) using `Colors.distinguishable_colors`.
4. Compute a layout: if not every bus is geo-pinned, run `NetworkLayout.sfdp` on the adjacency matrix (kwargs `K`, `C`, `tol`, `iterations`, with pinned positions); otherwise use the pinned coordinates directly.
5. Store `:x`/`:y`/`:name` back onto the graph via `set_prop!`.

Coordinates are projected to Web Mercator by `lonlat_to_webmercator` (multiple-dispatch methods for `Tuple`, `Shapefile.Point`, `Shapefile.Polygon`, and a `Vector{Union{Missing,Shapefile.Polygon}}`) before plotting, so shapefile polygons and network nodes share one projected coordinate system.

## Main public API / entry points

(Signatures verified against `src/plot_network.jl`.)

- `make_graph(sys::System; kwargs...) -> MetaGraph` — builds and lays out the graph. Key kwargs: `K` (SFDP spring constant), `color_by`, `name_accessor`, plus SFDP `C`/`tol`/`iterations`.
- `plot_net(g; kwargs...)` / `plot_net!(p::Plots.Plot, g; kwargs...)` — draw the network from a graph. Key kwargs: `lines::Bool`, `linecolor`, `linewidth`, `linealpha`, `nodesize`, `nodecolor`, `nodealpha`, `nodehover`, `shownodelegend`, `buffer`, `size`, `xlim`/`ylim`, `legend_font_color`. The `!` form overlays onto an existing plot (e.g. a basemap).
- `plot_map(sys::System, shapefile::AbstractString; kwargs...)` — one-shot convenience: `make_graph` + load shapefile + plot basemap + `plot_net!`. Map-styling kwargs are passed with a `map_` prefix (e.g. `map_linecolor`), which `plot_map` strips and forwards to the basemap `plot` call; un-prefixed kwargs go to the network layer.
- `plot_components!(p, components, color, markersize, label)` — add scatter dots for components (dispatched for a generic component iterator and for a `FlattenIteratorWrapper{Bus}`).

Not exported but used in the README/tests: `lonlat_to_webmercator`, `make_test_sys` (test-only). Reach them via the `PSM.` prefix.

## Plots backend (PlotlyJS vs GR) & how to select it

PSM draws with Plots.jl and does **not** force a backend. The user picks one before plotting:

- Interactive (hover tooltips work — the API sets `hover=` on series): call `PSM.Plots.plotlyjs()`, as in the README. Requires `PlotlyJS` to be installed in the active env (it is a `test/Project.toml` dep, not a package dep).
- Static / headless: `PSM.Plots.gr()`. The test suite runs on the **GR** backend — `test/test_maps.jl` asserts `typeof(p) == PSM.Plots.Plot{PSM.Plots.GRBackend}`.

## Conventions & gotchas

- **Backend is caller-chosen**: nothing in `src/` calls `gr()`/`plotlyjs()`. If you add a feature relying on `hover`, document that it needs the PlotlyJS backend.
- **Headless CI**: tests use GR with no display and only build plot objects (no `display`/`savefig`), so they run headless. Keep new tests display-free.
- **Geo fallback**: buses lacking `GeographicInfo` silently fall back to the San-Francisco default lon/lat and get a low alpha — don't mistake that for a bug when an ungeocoded system plots oddly.
- **PlotlyJS is not a package dep** — only `Plots`. Code in `src/` must not assume the PlotlyJS backend is available.

## Cross-package coupling

- **PowerSystems.jl** is the only Sienna dependency — PSM reads `Bus`, `Arc`, `Branch`, `AggregationTopology`, and `GeographicInfo` via PSY accessors (`get_components`, `get_name`, `get_lonlat` helper, etc.). Track PSY major bumps (currently compat `4`); accessor/attribute renames break PSM.
- **PowerGraphics.jl**: separate package for plotting *simulation results* (production cost, dispatch stacks). PSM is unrelated — it plots network *topology/geography*, not results. No code dependency either way.

## Running tests, docs, formatter (verified commands)

**Formatter — script exists** at `scripts/formatter/formatter_code.jl` (activates its own env, runs JuliaFormatter over `./src` and `./test`). Run it after any `.jl` change, before reporting done:

```sh
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

(There is no `.JuliaFormatter.toml`; format options are hard-coded in that script. CI also runs `.github/workflows/format-check.yml`.)

**Tests** — classic runner using `TestSetExtensions` + an `@includetests` macro (not ReTest). It auto-discovers `test_*.jl` files (currently just `test_maps.jl`). Deps incl. `PlotlyJS`, `CSV`, `DataFrames` live in `test/Project.toml`:

```sh
julia --project=test test/runtests.jl                # full suite
julia --project=test test/runtests.jl test_maps      # a single test file (name without .jl)
julia --project=test -e 'using Pkg; Pkg.instantiate()'
```

**Docs** — a `docs/` environment exists (`docs/make.jl`, `docs/Project.toml`); pages are `index.md` + `api.md`:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'   # first time
julia --project=docs docs/make.jl
```
