# frozen_string_literal: true

require "test_helper"

# Strategy names the planner has no rule for: a house's own name follows
# the rule its alias names (StrategySettings#aliases); one with neither is
# planned as comfort and said, its room named; asked about (uses, about),
# it is refused.
class StrategyNamesTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    ECO  = StrategySettings.new(aliases: { eco: :cheapest })

    def test_an_alias_follows_its_rule
        assert_equal Strategy.heat(room(:cheapest), StrategySettings.new),
                     Strategy.heat(room(:eco), ECO)
        assert_empty Plan.new([room(:eco)], settings: ECO).run.warnings
    end

    # Unknown: as comfort, not cheapest, and said with its zone.
    def test_an_unknown_name_is_planned_as_comfort_and_said
        settings = StrategySettings.new
        assert_equal Strategy.heat(room(:comfort), settings),
                     Strategy.heat(room(:eco), settings)
        notice = Plan.new([room(:eco)]).run.warnings
                     .find { it.kind == :unknown_strategy }
        assert_equal "office: strategy eco unknown, planned as comfort",
                     notice
        assert_equal "office", notice.zone
    end

    def test_asking_about_an_unknown_name_is_refused
        caps = { radiator: RADIATOR_CAPS, aircon: AIRCON_CAPS }
        assert_raises(ArgumentError) do
            Strategy.uses(:eco, StrategySettings.new, caps)
        end
        assert_raises(ArgumentError) { Strategy.about(:eco) }
        assert_equal Strategy.uses(:cheapest, StrategySettings.new, caps),
                     Strategy.uses(:eco, ECO, caps)
        assert_equal Strategy::ABOUT[:cheapest], Strategy.about(:eco, ECO)
    end

    def test_an_alias_to_no_rule_is_refused
        assert_raises(ArgumentError) do
            StrategySettings.new(aliases: { eco: :thrifty })
        end
    end

    private

    # A gas radiator and an electric unit, the room under its band.
    def room(strategy)
        valve = Radiator.new(ref: "1", label: "valve:1", caps: RADIATOR_CAPS,
                             temperature: nil, mode: :heat, target: 17.0,
                             range: 5.0..25.0, step: 0.5, least: 5.0)
        unit = Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                          system: "h:1", source: "pump", master: true,
                          temperature: nil, on: false, mode: :heat,
                          setpoint: 19.0, range: 15.0..30.0, step: 0.5)
        Room.new(zone: "office", band: BAND, strategy:, radiators: [valve],
                 aircons: [unit], measured: 18.0)
    end
end
