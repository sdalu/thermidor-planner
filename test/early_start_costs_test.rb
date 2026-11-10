# frozen_string_literal: true

require "test_helper"

# Early start over the periods ahead (Period): exclusions to come change
# the devices under every strategy; under cheapest, the costs choose the
# start (WarmUpCosts).
class EarlyStartCostsTest < Minitest::Test
    include Thermidor::Planner

    S = Thermidor::Schedule
    NIGHT = S::Setpoint.new(heat: 17, cool: 27)
    WAKE  = S::Setpoint.new(heat: 20, cool: 25)
    RADIATORS = Rise.new(base: 3.0, loss: 0.08)
    UNITS = Rise.new(base: 4.0, loss: 0.08)
    BOTH = Rise.new(base: 6.0, loss: 0.08)
    RATES = { heat: { radiators: RADIATORS, units: UNITS, both: BOTH } }
            .freeze

    # A red day: the heat pump cheap off-peak, dear from 60 min; gas the
    # same all along.
    RED = [Period.new(minutes: 0, costs: { "valve:VA1" => 0.20,
                                           "unit:1" => 0.02 }),
           Period.new(minutes: 60, costs: { "valve:VA1" => 0.20,
                                            "unit:1" => 0.40 })].freeze

    # Electricity excluded from 30 min: comfort's both become radiators,
    # so it starts sooner.
    def test_an_exclusion_ahead_starts_the_warm_up_sooner
        assert_nil start(room(:comfort), ahead(60, :comfort)).ahead
        peak = [Period.new(minutes: 0),
                Period.new(minutes: 30, excluded: %w[electricity])]
        found = start(room(:comfort), ahead(60, :comfort), periods: peak)
        assert found.ahead
    end

    # Heating on the heat pump off-peak and holding on gas beats waiting
    # and heating on gas alone.
    def test_cheapest_starts_sooner_off_peak
        found = start(room, ahead(150), periods: RED)
        assert found.ahead
        assert_equal :early_cheaper, found.notes.first.kind
        assert_match(/\d+ % cheaper than at \d+/, found.notes.first)
    end

    def test_a_saving_under_the_margin_keeps_the_latest_start
        settings = StrategySettings.new(cost_margin: 0.5)
        assert_nil start(room, ahead(150), periods: RED, strategy: settings)
            .ahead
    end

    # Comfort is timed by its rate alone, costs or not.
    def test_comfort_ignores_the_costs
        assert_nil start(room(:comfort), ahead(150, :comfort), periods: RED)
            .ahead
    end

    def test_a_device_without_a_cost_times_by_the_rate
        bare = [RED.first, Period.new(minutes: 60,
                                      costs: { "unit:1" => 0.40 })]
        found = start(room, ahead(150), periods: bare)
        assert_nil found.ahead
        late = start(room, ahead(70), periods: bare)
        assert late.ahead
        assert_equal "red: early start for +20.0 by its rate: no cost for " \
                     "valve:VA1 at 60 min", late.notes.first
    end

    # Cheapest's slow radiator never makes it in time; quick's both do,
    # and so warm the room on quick.
    def test_cheapest_warms_up_on_quick_when_its_own_is_not_in_time
        slow = { heat: { radiators: Rise.new(base: 1.0, loss: 0.02),
                         units: Rise.new(base: 3.0, loss: 0.02),
                         both: Rise.new(base: 4.0, loss: 0.02) } }
        costs = { "valve:VA1" => 0.10, "unit:1" => 0.11 }
        priced = room.with(costs:)
        found = start(priced, ahead(60), rates: slow)
        assert_equal :quick, found.strategy
    end

    private

    def start(room, *aheads, rates: RATES, periods: nil,
              strategy: StrategySettings.new)
        EarlyStart.new(strategy:)
                  .start(room, ahead: aheads, rates:, next_in: 10, periods:)
    end

    def ahead(minutes, strategy = :cheapest)
        Ahead.new(minutes:, band: WAKE, strategy:)
    end

    def room(strategy = :cheapest)
        Room.new(zone: "red", band: NIGHT, strategy:, radiators: [valve],
                 aircons: [unit], measured: 16.5, outside: 2.0)
    end

    def valve
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: 16.5, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5)
    end

    def unit
        Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "system:1", source: "pump", master: true,
                   temperature: 16.5, on: false, mode: :heat,
                   setpoint: 22.0, range: 16.0..30.0, step: 0.5)
    end
end
