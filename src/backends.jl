# Backend system for PowerSystemsMaps.jl, mirroring PowerGraphics.jl.
# Rendering and animation are provided by package extensions:
#   - CairoMakieExt  (loaded with `using CairoMakie`)
#   - PlotlyLightExt (loaded with `using PlotlyLight`)

abstract type PlottingBackend end

struct CairoMakieBackend <: PlottingBackend end
struct PlotlyLightBackend <: PlottingBackend end

const _CAIROMAKIE_PKGID =
    Base.PkgId(Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0"), "CairoMakie")
const _PLOTLYLIGHT_PKGID =
    Base.PkgId(Base.UUID("ca7969ec-10b3-423e-8d99-40f33abb42bf"), "PlotlyLight")

function _no_backend_loaded()
    throw(
        ArgumentError(
            "No plotting backend loaded. Run `using CairoMakie` or " *
            "`using PlotlyLight` before calling PowerSystemsMaps plotting functions.",
        ),
    )
end

"""
Return the active plotting backend, preferring CairoMakie when both are loaded. Throws if
no backend package has been imported.
"""
function default_backend()
    if haskey(Base.loaded_modules, _CAIROMAKIE_PKGID)
        return CairoMakieBackend()
    elseif haskey(Base.loaded_modules, _PLOTLYLIGHT_PKGID)
        return PlotlyLightBackend()
    end
    return _no_backend_loaded()
end
