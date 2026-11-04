# frozen_string_literal: true

require "test_helper"

# The planner on rooms given by hand: one heat pump (source "pump") with
# one system (h:1) whose master is unit 1.
class PlanTest < Minitest::Test
    include Thermidor::Planner

    Setpoint = Thermidor::Schedule::Setpoint
    BAND = Setpoint.new(heat: 20, cool: 24)

    def test_radiators_heat_to_the_band
        result = plan(room("bedroom", 18.0, radiator: :off))
        assert_equal [%i[mode off heat], [:target, 17.0, 20.0]],
                     changes(result, "valve:VA1")
    end

    def test_strategy_sets_who_heats
        office = room("office", 18.0, aircon: 1, radiator: :heat,
                                      strategy: :comfort)
        assert_equal [[:power, false, true], [:setpoint, 19.0, 19.5]],
                     changes(plan(office), "unit:1")
        quiet = room("office", 18.0, aircon: 1, radiator: :heat,
                                     strategy: :quiet)
        assert_empty changes(plan(quiet), "unit:1")
    end

    def test_the_comfort_gap_is_a_setting
        office = room("office", 18.0, aircon: 1, radiator: :heat,
                                      strategy: :comfort)
        result = Plan.new([office],
                          settings: StrategySettings.new(comfort: 2.0)).run
        assert_equal [[:power, false, true], [:setpoint, 19.0, 18.0]],
                     changes(result, "unit:1")
    end

    def test_a_conflict_is_settled_by_radiators_first
        result = plan(room("living", 18.0, aircon: 1, radiator: :heat),
                      room("office", 26.0, aircon: 2),
                      room("guest", 26.0, aircon: 3))
        assert_equal [%i[mode heat cool]], changes(result, "h:1")
        assert_equal [[:power, false, true], [:setpoint, nil, 24.0]],
                     changes(result, "unit:2")
        assert_empty result.warnings
    end

    def test_cheapest_heats_with_the_air_conditioning_only
        room = room("office", 18.0, aircon: 1, radiator: :heat,
                                    strategy: :cheapest)
        result = plan(room)
        assert_equal [[:target, 17.0, 5.0]], changes(result, "valve:VA1")
        assert_equal [[:power, false, true], [:setpoint, 19.0, 20.0]],
                     changes(result, "unit:1")
    end

    # Not heating is the least target, never off: a thermostat's own
    # driver may switch an off one on again. One off already is left so.
    def test_a_radiator_not_heating_goes_to_its_least
        off = room("office", 18.0, aircon: 1, radiator: :off,
                                   strategy: :cheapest)
        assert_empty changes(plan(off), "valve:VA1")
    end

    def test_an_excluded_energy_does_not_heat
        red    = { excluded: %w[electricity] }
        office = room("office", 18.0, aircon: 1, radiator: :heat).with(**red)
        result = plan(office)
        assert_empty changes(result, "unit:1")
        alone = plan(room("attic", 18.0, aircon: 2).with(**red))
        assert_equal ["attic: needs heat, but electricity is excluded now"],
                     alone.warnings
    end

    def test_frost_is_left_to_the_radiators
        frost = Setpoint.new(heat: 7, cool: nil)
        room = Room.new(zone: "attic", band: frost, strategy: :cheapest,
                        radiators: [radiator(:off)],
                        aircons: [aircon(1, 18.0).with(on: true)])
        result = plan(room)
        assert_equal [[:power, true, false]], changes(result, "unit:1")
        assert_equal [%i[mode off heat], [:target, 17.0, 7.0]],
                     changes(result, "valve:VA1")
    end

    def test_the_most_rooms_win_and_the_others_are_warned
        result = plan(room("living", 18.0, aircon: 1),
                      room("office", 26.0, aircon: 2),
                      room("guest", 17.0, aircon: 3))
        assert_empty changes(result, "h:1")
        assert_equal ["office: needs cool, but pump heat"], result.warnings
    end

    def test_nothing_needed_keeps_the_direction
        result = plan(room("living", 22.0, aircon: 1))
        assert_empty changes(result, "h:1")
    end

    private

    def plan(*rooms) = Plan.new(rooms).run

    def changes(result, device)
        result.actions.select { it.device == device }
              .map { [it.setting, it.from, it.to] }
    end

    def room(zone, temperature, aircon: nil, radiator: nil,
             strategy: :quick)
        Room.new(zone:, band: BAND, strategy:,
                 radiators: radiator ? [radiator(radiator)] : [],
                 aircons: aircon ? [aircon(aircon, temperature)] : [])
    end

    def radiator(mode)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: nil, mode:, target: 17.0, range: 5.0..25.0,
                     step: 0.5, least: 5.0)
    end

    def aircon(id, temperature)
        Aircon.new(ref: "h:1:#{id}", label: "unit:#{id}",
                   caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: id == 1, temperature:,
                   on: false, mode: :heat, setpoint: 19.0, range: 15.0..30.0,
                   step: 0.5)
    end
end
