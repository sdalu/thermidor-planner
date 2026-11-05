# frozen_string_literal: true

require "test_helper"

# A cost margin under cheapest (StrategySettings#cost_margin): the
# device that led last (room.led) keeps the lead while its kWh of heat
# costs no more than the cheapest's by that fraction, so a crossover
# hovered around does not swap the lead each run.
class CostMarginTest < Minitest::Test
    include Thermidor::Planner

    BAND   = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    MARGIN = StrategySettings.new(cost_margin: 0.05)

    def test_the_last_lead_keeps_it_within_the_margin
        room = cheap(valve: 0.100, unit: 0.098, led: %w[valve:a])
        assert_equal({ "valve:a" => 0.0, "unit:a" => nil },
                     Roles.new(room, 20.0).offsets(:cheapest, MARGIN))
    end

    def test_past_the_margin_the_cheapest_takes_it
        room = cheap(valve: 0.100, unit: 0.090, led: %w[valve:a])
        assert_equal({ "valve:a" => nil, "unit:a" => 0.0 },
                     Roles.new(room, 20.0).offsets(:cheapest, MARGIN))
    end

    def test_without_a_margin_or_a_last_lead_the_cheapest_leads
        room = cheap(valve: 0.100, unit: 0.098, led: %w[valve:a])
        cheapest = { "valve:a" => nil, "unit:a" => 0.0 }
        assert_equal cheapest, Roles.new(room, 20.0)
                                    .offsets(:cheapest, StrategySettings.new)
        assert_equal cheapest, Roles.new(room.with(led: nil), 20.0)
                                    .offsets(:cheapest, MARGIN)
    end

    # A last lead that no longer takes part (its energy excluded now)
    # holds nothing.
    def test_a_last_lead_not_taking_part_holds_nothing
        room = cheap(valve: 0.100, unit: 0.098, led: %w[valve:a])
               .with(excluded: %w[gas])
        assert_equal({ "unit:a" => 0.0 },
                     Roles.new(room, 20.0, room.excluded)
                          .offsets(:cheapest, MARGIN))
    end

    def test_a_negative_margin_is_refused
        assert_raises(ArgumentError) { StrategySettings.new(cost_margin: -0.1) }
    end

    private

    def cheap(valve:, unit:, led:)
        Room.new(zone: "a", band: BAND, strategy: :cheapest,
                 radiators: [radiator], aircons: [aircon], measured: 19.0,
                 costs: { "valve:a" => valve, "unit:a" => unit }, led:)
    end

    def radiator
        Radiator.new(ref: "a", label: "valve:a", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end

    def aircon
        Aircon.new(ref: "a", label: "unit:a", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on: true, mode: :heat, setpoint: 20.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
