# frozen_string_literal: true

require "test_helper"

# What the survey found: a room its heat pump leaves needing heat is
# heated by its radiators; a room needing heat that nothing heats is
# said, whatever the reason; a range open at an end is no bound there.
class SurveyFixesTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    AWAY = Thermidor::Schedule::Setpoint.new(heat: 16, cool: 30)
    HELD_OFF = { "pump" => PumpState.new(held: nil) }.freeze

    # cheapest rests the radiator for the unit; the pump held off, the
    # radiator heats at the band instead of resting.
    def test_radiators_heat_a_room_its_pump_leaves_cold
        result = Plan.new([away], pumps: HELD_OFF).run
        assert_includes changes(result), ["valve:1", :target, 5.0, 16.0]
    end

    # The pump heating, the plan is as before: the radiator rests.
    def test_a_pump_heating_keeps_the_radiators_resting
        result = Plan.new([away]).run
        refute(changes(result).any? { it[0] == "valve:1" })
    end

    # Idle (nobody needs anything, the pump off), cheapest still waits
    # for the pump: the radiator is not lifted.
    def test_an_idle_pump_does_not_wake_the_radiators
        idle = away.with(measured: 17.0)
        result = Plan.new([idle], pumps: HELD_OFF).run
        refute_includes changes(result), ["valve:1", :target, 5.0, 16.0]
    end

    def test_a_room_nothing_can_heat_as_low_as_its_band_is_said
        frost = Thermidor::Schedule::Setpoint.new(heat: 12, cool: 30)
        room = Room.new(zone: "r", band: frost, strategy: :quick,
                        radiators: [], aircons: [unit(on: true)],
                        measured: 10.0)
        assert_includes Plan.new([room]).run.warnings,
                        "r: needs heat, but no device heats as low as 12.0 °C"
    end

    def test_a_room_with_no_heating_device_is_said
        cold_only = AIRCON_CAPS.with(heat: false)
        room = Room.new(zone: "r", band: BAND, strategy: :quick,
                        radiators: [],
                        aircons: [unit(on: false).with(caps: cold_only)],
                        measured: 18.0)
        assert_includes Plan.new([room]).run.warnings,
                        "r: needs heat, but no device can heat it"
    end

    # The excluded-energy sentence stays as it was.
    def test_an_excluded_energy_is_said_as_before
        room = Room.new(zone: "r", band: BAND, strategy: :quick,
                        radiators: [], aircons: [unit(on: false)],
                        measured: 18.0, excluded: %w[electricity])
        assert_equal ["r: needs heat, but electricity is excluded now"],
                     Plan.new([room]).run.warnings
    end

    def test_a_unit_s_range_open_at_both_ends_is_no_bound
        assert_includes changes(Plan.new([open_room]).run),
                        ["unit:1", :setpoint, 16.0, 20.0]
    end

    # cheapest rests the radiator: its range open below, its own least.
    def test_a_radiator_s_range_open_below_falls_back_on_its_least
        resting = Radiator.new(ref: "1", label: "valve:1",
                               caps: RADIATOR_CAPS, temperature: nil,
                               mode: :heat, target: 17.0, range: nil..25.0,
                               step: 0.5, least: 5.0)
        cheap = open_room.with(strategy: :cheapest, radiators: [resting])
        assert_includes changes(Plan.new([cheap]).run),
                        ["valve:1", :target, 17.0, 5.0]
    end

    private

    def changes(result)
        result.actions.map { [it.device, it.setting, it.from, it.to] }
    end

    # cheapest, away, the room at 14 °C: a radiator resting at 5 °C and
    # a unit on the pump.
    def away
        valve = Radiator.new(ref: "1", label: "valve:1", caps: RADIATOR_CAPS,
                             temperature: nil, mode: :heat, target: 5.0,
                             range: 5.0..25.0, step: 0.5, least: 5.0)
        Room.new(zone: "r", band: AWAY, strategy: :cheapest,
                 radiators: [valve], aircons: [unit(on: true)],
                 measured: 14.0)
    end

    def open_room
        open = unit(on: false).with(range: nil..nil, ranges: {})
        Room.new(zone: "r", band: BAND, strategy: :quick, radiators: [],
                 aircons: [open], measured: 18.0)
    end

    def unit(on:)
        Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on:, mode: :heat, setpoint: 16.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
