# frozen_string_literal: true

require "test_helper"

# A radiator not to heat goes to its least target: its range's least
# first, else its own; with neither it is left as it is, said.
class PlanLeastTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 24)

    def test_its_own_least_without_a_range
        assert_equal [[:target, 17.0, 5.0]], changes(plan(range: nil))
    end

    def test_its_range_s_least_first
        assert_equal [[:target, 17.0, 7.0]], changes(plan(range: 7.0..25.0))
    end

    def test_with_neither_it_is_left_and_said
        result = plan(range: nil, least: nil)
        assert_empty changes(result)
        assert_equal ["office: valve:VA1 has no least target: left as it is"],
                     result.warnings
    end

    private

    # cheapest heats with the unit alone: the radiator, heating at 17 °C,
    # is not to heat.
    def plan(**radiator)
        Plan.new([Room.new(zone: "office", band: BAND, strategy: :cheapest,
                           radiators: [radiator(**radiator)], aircons: [unit],
                           measured: 18.0)]).run
    end

    def changes(result)
        result.actions.select { it.device == "valve:VA1" }
              .map { [it.setting, it.from, it.to] }
    end

    def radiator(range:, least: 5.0)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0, range:,
                     step: 0.5, least:)
    end

    def unit
        Aircon.new(ref: "h:1:1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on: true, mode: :heat, setpoint: 20.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
