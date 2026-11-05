# frozen_string_literal: true

require "test_helper"

# What the hunt of 2026-11-05 found, each on its trigger: stepping aside
# by radiators able to heat; no margin from a stopped compressor; the
# least times holding setpoints too; an urgent start ending the rest;
# settings with no off refusing nil; mild lead backing up only units
# that heat; radiators heating while the pump rests.
class HuntFixesTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # x needs cool, y needs heat under cheapest with a radiator: y steps
    # aside, x is cooled, y's radiator heats.
    def test_a_room_with_radiators_steps_aside_under_cheapest
        result = plan([room("x", 27.0, mode: :cool),
                       room("y", 18.0, mode: :cool, strategy: :cheapest,
                                       valve: true)])
        assert_empty(actions(result).select { it[1] == :mode })
        assert_includes actions(result), ["valve:y", :target, 5.0, 20.0]
        refute(result.warnings.any? { it.start_with?("x: needs cool") })
    end

    # Hysteresis, the system left in heat, no unit on, the compressor
    # stopped: no margin, the pump turns to cool.
    def test_no_margin_from_a_stopped_pump_in_heat
        hot = room("a", 26.3)
        hysteresis = pump(switch: :hysteresis)
        stopped = { "pump" => PumpState.new(running: false) }
        assert_includes actions(plan([hot], hysteresis, stopped)),
                        ["h:1", :mode, :heat, :cool]
        assert_includes actions(plan([hot], hysteresis)),
                        ["h:1", :mode, :heat, :cool]
    end

    # min_off, stopped 3 min ago: an idle unit's setpoint is not raised
    # into a call.
    def test_the_least_rest_holds_a_setpoint_too
        idle = room("a", 19.5, on: true, setpoint: 18.0)
        rest = state(running: false, ago: 3)
        assert_empty actions(plan([idle], pump(min_off: 10), rest))
    end

    # min_on, started 5 min ago: the only caller's setpoint is not
    # lowered out of its call by a band half a degree lower.
    def test_the_least_run_holds_a_setpoint_too
        lower = room("a", 19.0, on: true).with(band: band(18.5))
        run = state(running: true, ago: 5)
        assert_empty actions(plan([lower], pump(min_on: 15), run))
    end

    # An away band leaves the room more than urgent above it: the run
    # ends, heating further would be waste.
    def test_a_room_urgent_past_a_lowered_band_ends_the_least_run
        away = room("a", 19.0, on: true).with(band: band(16))
        run = state(running: true, ago: 5)
        assert_includes actions(plan([away], pump(min_on: 15), run)),
                        ["unit:a", :setpoint, 20.0, 16.0]
    end

    # min_off, one room urgent: the pump starts, every room under its
    # target starts with it, and nothing is said kept stopped.
    def test_an_urgent_room_starts_every_unit_under_its_target
        result = plan([room("a", 18.5), room("b", 19.5)], pump(min_off: 10),
                      state(running: false, ago: 3))
        assert_includes actions(result), ["unit:a", :power, false, true]
        assert_includes actions(result), ["unit:b", :power, false, true]
        assert(result.warnings.none? { it.include?("kept stopped") })
    end

    def test_settings_with_no_off_refuse_nil
        %i[margin mild_deadband urgent lead_gap].each do |key|
            assert_raises(ArgumentError, key.to_s) do
                PumpSettings.new(key => nil)
            end
        end
    end

    # quiet rests the loud unit; mild lead leads with the radiator and
    # leaves the unit resting, not backing up.
    def test_mild_lead_backs_up_only_units_that_heat
        quiet = room("a", 19.5, strategy: :quiet, valve: true)
                .with(outside: 12.0)
        lead = pump(mild_lead: 8.0)
        assert_equal({ "valve:a" => 20.0, "unit:a" => nil },
                     Strategy.heat(quiet, lead))
    end

    # cheapest, min_off holding the unit off: the room's radiator heats
    # meanwhile.
    def test_radiators_heat_while_the_pump_rests
        cold = room("a", 19.2, strategy: :cheapest, valve: true)
        result = plan([cold], pump(min_off: 10), state(running: false, ago: 3))
        assert_includes actions(result), ["valve:a", :target, 5.0, 20.0]
        refute(actions(result).any? { it[0] == "unit:a" })
    end

    private

    def pump(**) = StrategySettings.new(pump: PumpSettings.new(**))

    def band(heat) = Thermidor::Schedule::Setpoint.new(heat:, cool: 30)

    def state(running:, ago:)
        { "pump" => PumpState.new(running:, switched_ago: ago) }
    end

    def plan(rooms, settings = StrategySettings.new, pumps = {})
        Plan.new(rooms, settings:, pumps:).run
    end

    def actions(result)
        result.actions.map { [it.device, it.setting, it.from, it.to] }
    end

    # name at temperature under strategy, valve: a radiator resting;
    # its unit (unit:) off in heat at 20 unless said, the first named
    # its system's master.
    def room(name, temperature, strategy: :quick, valve: false, **unit)
        Room.new(zone: name, band: BAND, strategy:,
                 aircons: [unit(name, **unit)],
                 radiators: valve ? [radiator(name)] : [],
                 measured: temperature)
    end

    def unit(name, mode: :heat, on: false, setpoint: 20.0)
        Aircon.new(ref: name, label: "unit:#{name}", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump",
                   master: %w[a x].include?(name), temperature: nil, on:,
                   mode:, setpoint:, range: 15.0..30.0, step: 0.5)
    end

    def radiator(name)
        Radiator.new(ref: name, label: "valve:#{name}", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 5.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
