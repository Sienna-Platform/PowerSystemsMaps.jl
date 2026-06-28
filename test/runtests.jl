using Test
using TestSetExtensions
using Logging
using PowerSystems
using CairoMakie  # load the backend before PowerSystemsMaps so CairoMakieExt is active
using PowerSystemsMaps
import DataFrames
import CSV
import Dates

const PSY = PowerSystems
const PSM = PowerSystemsMaps
const IS = PSY.IS

const BASE_DIR = dirname(dirname(pathof(PowerSystemsMaps)))
const TEST_DIR = joinpath(BASE_DIR, "test")
const LOG_FILE = "PowerSystemsMaps-test.log"

LOG_LEVELS = Dict(
    "Debug" => Logging.Debug,
    "Info" => Logging.Info,
    "Warn" => Logging.Warn,
    "Error" => Logging.Error,
)

function make_test_sys()
    sys = System(joinpath(TEST_DIR, "test_data", "case_ACTIVSg200.m"))
    locs = PSY.CSV.read(
        joinpath(TEST_DIR, "test_data", "bus_locs.csv"),
        PSY.DataFrames.DataFrame,
    )
    for row in PSY.DataFrames.eachrow(locs)
        bus = first(get_components(x -> occursin(row.name, get_name(x)), Bus, sys))
        if !isnothing(bus)
            add_supplemental_attribute!(
                sys,
                bus,
                GeographicInfo(;
                    geo_json = Dict(
                        "type" => "Point",
                        "coordinates" => [row.longitude, row.latitude],
                    ),
                ),
            )
        end
    end
    return sys
end

macro includetests(testarg...)
    if length(testarg) == 0
        tests = []
    elseif length(testarg) == 1
        tests = testarg[1]
    else
        error("@includetests takes zero or one argument")
    end

    quote
        tests = $tests
        rootfile = TEST_DIR
        if length(tests) == 0
            tests = readdir(rootfile)
            tests = filter(
                f ->
                    startswith(f, "test_") && endswith(f, ".jl") && f != basename(rootfile),
                tests,
            )
        else
            tests = map(f -> string(f, ".jl"), tests)
        end
        println()
        for test in tests
            print(splitext(test)[1], ": ")
            include(joinpath(TEST_DIR, test))
            println()
        end
    end
end

function get_logging_level(env_name::String, default)
    level = get(ENV, env_name, default)
    log_level = get(LOG_LEVELS, level, nothing)
    if log_level === nothing
        error("Invalid log level $level: Supported levels: $(values(LOG_LEVELS))")
    end

    return log_level
end

function run_tests()
    console_level = get_logging_level("PS_CONSOLE_LOG_LEVEL", "Error")
    console_logger = ConsoleLogger(stderr, console_level)
    file_level = get_logging_level("PS_LOG_LEVEL", "Info")

    IS.open_file_logger(LOG_FILE, file_level) do file_logger
        levels = (Logging.Info, Logging.Warn, Logging.Error)
        multi_logger =
            IS.MultiLogger([console_logger, file_logger], IS.LogEventTracker(levels))
        global_logger(multi_logger)

        # Testing Topological components of the schema
        @time @testset "Begin PowerSystemsMaps tests" begin
            @includetests ARGS
        end

        @test length(IS.get_log_events(multi_logger.tracker, Logging.Error)) == 0

        @info IS.report_log_summary(multi_logger)
    end
end

logger = global_logger()

try
    run_tests()
finally
    # Guarantee that the global logger is reset.
    global_logger(logger)
    nothing
end
