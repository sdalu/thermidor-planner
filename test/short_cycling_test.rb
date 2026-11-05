# frozen_string_literal: true

require "test_helper"

# Against a heat pump's short cycles (PumpSettings), each off until set:
# a wider on/off gap for the units in mild weather, a least time on and
# off, and the radiators leading in mild weather when little heat is
# needed.
class ShortCyclingTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    LOUD = AIRCON_CAPS
    LEAD = StrategySettings.new(pump: PumpSettings.new(mild_lead: 8.0))

    def test_nothing_changes_until_set
        assert_equal [[:power, false, true]],
                     power(plan(room(19.5, on: false, outside: 12.0)))
    end

    # Mild (12 °C ≥ 8), off: the unit waits for the room a degree under
    # its target.
    def test_mild_weather_starts_a_unit_a_degree_later
        mild = pump(mild: 8.0)
        assert_empty power(plan(room(19.5, on: false, outside: 12.0), mild))
        assert_equal [[:power, false, true]],
                     power(plan(room(18.9, on: false, outside: 12.0), mild))
    end

    # Mild, on: the unit runs up to its target, then goes off.
    def test_mild_weather_runs_a_unit_up_to_its_target
        mild = pump(mild: 8.0)
        assert_empty power(plan(room(19.5, on: true, outside: 12.0), mild))
        assert_equal [[:power, true, false]],
                     power(plan(room(20.0, on: true, outside: 12.0), mild))
    end

    def test_cold_or_unknown_weather_keeps_the_gap_as_it_is
        mild = pump(mild: 8.0)
        assert_equal [[:power, false, true]],
                     power(plan(room(19.5, on: false, outside: 5.0), mild))
        assert_equal [[:power, false, true]],
                     power(plan(room(19.5, on: false, outside: nil), mild))
    end

    # quiet rests the loud unit: switched on 5 minutes ago, it stays on
    # (said) until its 15; after them, off.
    def test_a_unit_stays_on_its_least_time
        least = pump(min_on: 15)
        early = plan(quiet(on: true, ago: 5), least)
        assert_empty power(early)
        assert_includes early.warnings,
                        "r: unit:1 kept on: switched 5 min ago, at least 15"
        assert_equal [[:power, true, false]],
                     power(plan(quiet(on: true, ago: 20), least))
    end

    # Excluded now, or the room a degree above its band: off at once.
    def test_an_exclusion_or_a_room_too_warm_ends_the_least_time
        least = pump(min_on: 15)
        red = room(19.5, on: true, ago: 5).with(excluded: %w[electricity])
        assert_equal [[:power, true, false]], power(plan(red, least))
        hot = quiet(on: true, ago: 5).with(measured: 21.5)
        assert_equal [[:power, true, false]], power(plan(hot, least))
    end

    def test_a_unit_stays_off_its_least_time_unless_the_room_is_cold
        least = pump(min_off: 10)
        early = plan(room(19.5, on: false, ago: 3), least)
        assert_empty power(early)
        assert_includes early.warnings,
                        "r: unit:1 kept off: switched 3 min ago, at least 10"
        assert_equal [[:power, false, true]],
                     power(plan(room(18.5, on: false, ago: 3), least))
        assert_equal [[:power, false, true]],
                     power(plan(room(19.5, on: false, ago: nil), least))
    end

    # cheapest leads with the unit; mild and a room less than a degree
    # under its band, the radiator leads and the unit backs up.
    def test_radiators_lead_in_mild_weather
        assert_equal({ "valve:1" => nil, "unit:1" => 20.0 },
                     Strategy.heat(cheap, StrategySettings.new))
        assert_equal({ "valve:1" => 20.0, "unit:1" => 19.5 },
                     Strategy.heat(cheap, LEAD))
    end

    # A room a degree and more under its band, or cold weather: the
    # strategy as it is.
    def test_a_cold_room_or_cold_weather_keeps_the_strategy
        unit_leads = { "valve:1" => nil, "unit:1" => 20.0 }
        assert_equal unit_leads,
                     Strategy.heat(cheap.with(measured: 18.5), LEAD)
        assert_equal unit_leads,
                     Strategy.heat(cheap.with(outside: 5.0), LEAD)
    end

    def test_a_negative_setting_is_refused
        assert_raises(ArgumentError) { PumpSettings.new(min_on: -1) }
        assert_raises(ArgumentError) { PumpSettings.new(mild_deadband: -1) }
    end

    private

    def pump(**) = StrategySettings.new(pump: PumpSettings.new(**))

    # cheapest with a radiator beside the unit, mild, the room at 19.5.
    def cheap
        room(19.5, on: true, strategy: :cheapest, valve: true,
                   outside: 12.0)
    end

    def plan(room, settings = StrategySettings.new)
        Plan.new([room], settings:).run
    end

    def power(result)
        result.actions.select { it.setting == :power }
              .map { [it.setting, it.from, it.to] }
    end

    # A room at temperature, its unit on or off, switched ago minutes
    # back; valve: with a radiator beside it; fields: the room's others.
    def room(temperature, on:, ago: nil, valve: false, **fields)
        unit = Aircon.new(ref: "1", label: "unit:1", caps: LOUD,
                          system: "h:1", source: "pump", master: true,
                          temperature: nil, on:, mode: :heat,
                          setpoint: 20.0, range: 15.0..30.0, step: 0.5,
                          switched_ago: ago)
        Room.new(zone: "r", band: BAND, strategy: :quick, aircons: [unit],
                 radiators: valve ? [radiator] : [], measured: temperature,
                 **fields)
    end

    # quiet, a quiet radiator beside the loud unit, the room at 19.5.
    def quiet(**) = room(19.5, strategy: :quiet, valve: true, **)

    def radiator
        Radiator.new(ref: "1", label: "valve:1", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
