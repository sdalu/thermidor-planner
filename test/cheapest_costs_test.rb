# frozen_string_literal: true

require "test_helper"

# cheapest by the costs the caller gives (room.costs, a kWh of heat per
# device label): the cheapest devices heat, together when they cost the
# same; any device without a cost leaves the rule to its heat pumps.
class CheapestCostsTest < Minitest::Test
    include Thermidor::Planner

    BAND  = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    LOUD  = RADIATOR_CAPS.with(quiet: false)
    GAS_U = AIRCON_CAPS.with(energy: "gas")

    def test_the_cheapest_device_heats_by_its_cost
        costs = { "valve:q" => 0.12, "unit:1" => 0.08 }
        assert_equal({ "valve:q" => nil, "unit:1" => 0.0 },
                     offsets([valve("q")], [unit(1)], costs))
        dearer = { "valve:q" => 0.06, "unit:1" => 0.08 }
        assert_equal({ "valve:q" => 0.0, "unit:1" => nil },
                     offsets([valve("q")], [unit(1)], dearer))
    end

    # Two radiators without a heat pump: the cheaper one alone, which
    # the heat-pump rule could not tell apart.
    def test_costs_rank_radiators_with_no_heat_pump
        costs = { "valve:q" => 0.15, "valve:l" => 0.10, "unit:1" => 0.20 }
        found = offsets([valve("q"), valve("l", LOUD)], [unit(1, GAS_U)],
                        costs)
        assert_equal({ "valve:q" => nil, "valve:l" => 0.0, "unit:1" => nil },
                     found)
    end

    def test_equal_costs_heat_together
        costs = { "valve:q" => 0.1, "unit:1" => 0.1 }
        assert_equal({ "valve:q" => 0.0, "unit:1" => 0.0 },
                     offsets([valve("q")], [unit(1)], costs))
    end

    # A cost missing for one device: the heat-pump rule, as with none.
    def test_a_missing_cost_falls_back_on_the_heat_pumps
        costs = { "valve:q" => 0.01 }
        assert_equal({ "valve:q" => nil, "unit:1" => 0.0 },
                     offsets([valve("q")], [unit(1)], costs))
    end

    # The costs choose under cheapest only.
    def test_other_strategies_ignore_the_costs
        costs = { "valve:q" => 0.5, "unit:1" => 0.01 }
        assert_equal({ "valve:q" => 0.0, "unit:1" => nil },
                     offsets([valve("q")], [unit(1)], costs, :quiet))
    end

    def test_the_plan_heats_with_the_cheapest
        room = Room.new(zone: "hall", band: BAND, strategy: :cheapest,
                        radiators: [valve("q")], aircons: [unit(1)],
                        measured: 18.0,
                        costs: { "valve:q" => 0.06, "unit:1" => 0.08 })
        actions = Plan.new([room]).run.actions
        assert_includes actions.map { [it.device, it.setting, it.to] },
                        ["valve:q", :target, 20.0]
        refute(actions.any? { it.device == "unit:1" && it.setting == :power })
    end

    private

    def offsets(radiators, aircons, costs, strategy = :cheapest)
        room = Room.new(zone: "hall", band: BAND, strategy:, radiators:,
                        aircons:, costs:)
        Roles.new(room, 20.0).offsets(strategy, StrategySettings.new)
    end

    def valve(name, caps = RADIATOR_CAPS)
        Radiator.new(ref: name, label: "valve:#{name}", caps:,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end

    def unit(id, caps = AIRCON_CAPS)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps:, system: "h:1",
                   source: "pump", master: true, temperature: nil, on: false,
                   mode: :heat, setpoint: 19.0, range: 15.0..30.0, step: 0.5)
    end
end
