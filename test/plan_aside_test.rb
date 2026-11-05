# frozen_string_literal: true

require "test_helper"

# A system set aside (aside:) is left to itself: its mode is not set,
# its units get no action, and their rooms do not vote through them.
class PlanAsideTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # office needs heat, its unit off in a system set aside: neither
    # the unit nor its system is touched.
    def test_a_unit_set_aside_gets_no_action
        office = room("office", unit(1, "h:2", on: false), 18.0)
        assert_empty plan([office], aside: %w[h:2]).actions
        refute_empty plan([office]).actions
    end

    # guest, hot, has only a unit set aside: it does not tie the pump
    # against office, its unit is not switched off, nor said unserved.
    def test_a_room_does_not_vote_through_a_unit_set_aside
        office = room("office", unit(1, "h:1"), 18.0)
        guest = room("guest", unit(2, "h:2", mode: :cool), 28.0)
        result = plan([office, guest], aside: %w[h:2])
        refute(result.actions.any? { it.device == "unit:2" })
        refute(result.actions.any? { it.device == "h:2" })
        assert_empty result.warnings
    end

    # Under cheapest, a room needing heat whose only unit is set aside
    # is its radiator's, as one its pump leaves cold.
    def test_a_room_whose_unit_is_set_aside_is_its_radiators
        valve = Radiator.new(ref: "1", label: "valve:1",
                             caps: RADIATOR_CAPS, temperature: nil,
                             mode: :heat, target: 5.0, range: 5.0..25.0,
                             step: 0.5, least: 5.0)
        office = room("office", unit(1, "h:2", on: false), 18.0)
                 .with(strategy: :cheapest, radiators: [valve])
        actions = plan([office], aside: %w[h:2]).actions
        targets = actions.map { [it.device, it.to] }
        assert_includes targets, ["valve:1", 20.0]
    end

    private

    def plan(rooms, aside: []) = Plan.new(rooms, aside:).run

    def room(zone, unit, temperature)
        Room.new(zone:, band: BAND, strategy: :quick, radiators: [],
                 aircons: [unit], measured: temperature)
    end

    def unit(id, system, on: true, mode: :heat)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps: AIRCON_CAPS,
                   system:, source: "pump", master: true, temperature: nil,
                   on:, mode:, setpoint: 20.0, range: 15.0..30.0, step: 0.5)
    end
end
