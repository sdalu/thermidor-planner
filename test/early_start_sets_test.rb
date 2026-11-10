# frozen_string_literal: true

require "test_helper"

# Early start's devices (WarmUpSets): the set the warm-up's strategy
# heats with picks the rate; warmup, hurry and fallback choose and
# replace it.
class EarlyStartSetsTest < Minitest::Test
    include Thermidor::Planner

    S = Thermidor::Schedule
    NIGHT = S::Setpoint.new(heat: 17, cool: 27)
    WAKE  = S::Setpoint.new(heat: 20, cool: 25)
    RADIATORS = Rise.new(base: 3.0, loss: 0.08, delay: 15)
    UNITS = Rise.new(base: 2.0, loss: 0.08)
    BOTH = Rise.new(base: 6.0, loss: 0.08, delay: 5)
    RATES = { heat: { radiators: RADIATORS, units: UNITS, both: BOTH } }
            .freeze

    # Comfort's gap-behind unit calls too, far under the band.
    def test_comfort_with_a_radiator_and_a_unit_runs_both
        assert_match "(both,", said(start(room, ahead(55)))
    end

    def test_quiet_leaves_the_loud_unit_out
        assert_match "(radiators,", said(start(room, ahead(140, :quiet)))
    end

    def test_an_excluded_energy_drops_its_class
        gas_only = room.with(excluded: %w[electricity])
        assert_match "(radiators,", said(start(gas_only, ahead(140)))
    end

    def test_both_without_a_rate_takes_the_faster_single
        rates = { heat: { radiators: RADIATORS, units: UNITS } }
        found = start(room, ahead(140), rates:)
        assert_match "(both, 1.8 °C/h)", said(found)
    end

    # A device an energy rule caps under the aim cannot bring the room
    # there.
    def test_a_device_capped_under_the_aim_is_left_out
        capped = room.with(effects: Effects.none.with(caps: { "gas" => 1.0 }))
        assert_match "(units,", said(start(capped, ahead(140)))
    end

    def test_held_devices_leave_no_device_to_reach_it
        held = room.with(radiators: [], aircons: [], held: [valve])
        found = start(held, ahead(60))
        assert_nil found.ahead
        assert_equal ["red: no early start for +20.0: no device to reach it"],
                     found.notes
    end

    def test_no_rate_starts_nothing
        found = start(room, ahead(60), rates: {})
        assert_nil found.ahead
        assert_equal ["red: no early start for +20.0: no rate for both"],
                     found.notes
    end

    def test_a_fallback_starts_fixed_minutes_ahead
        settings = EarlyStartSettings.new(fallback: 60)
        assert_nil start(room, ahead(75), rates: {}, settings:).ahead
        found = start(room, ahead(70), rates: {}, settings:)
        assert found.ahead
        assert_equal ["red: early start for +20.0, 60 min ahead " \
                      "(no rate, fallback)"], found.notes
    end

    # warmup: the strategy every warm-up runs, its due time its own.
    def test_warmup_quick_runs_quick
        settings = EarlyStartSettings.new(warmup: :quick)
        quiet = ahead(140, :quiet)
        assert_nil start(room, quiet, settings:).ahead
        found = start(room, ahead(55, :quiet), settings:)
        assert_equal :quick, found.strategy
        assert_match "(both,", said(found)
    end

    # hurry: quiet's radiators late, quick's both in time: quick, said;
    # off, quiet kept, late.
    def test_a_late_warm_up_hurries_on_quick
        late = ahead(60, :quiet)
        assert_equal :quiet, start(room, late).strategy
        settings = EarlyStartSettings.new(hurry: true)
        found = start(room, late, settings:)
        assert_equal :quick, found.strategy
        assert_equal :early_hurry, found.notes.first.kind
    end

    def test_no_hurry_when_quick_is_no_faster
        settings = EarlyStartSettings.new(hurry: true)
        rates = { heat: { radiators: RADIATORS } }
        assert_equal :quiet,
                     start(room, ahead(60, :quiet), rates:, settings:).strategy
    end

    # Kept by the latch, never switched after.
    def test_the_strategy_started_is_kept
        settings = EarlyStartSettings.new(hurry: true)
        kept = start(room, ahead(30, :quiet, started: :quiet), settings:)
        assert_equal :quiet, kept.strategy
    end

    private

    def said(found) = found.notes.first.to_s

    def start(room, *aheads, rates: RATES, settings: EarlyStartSettings.new)
        EarlyStart.new(settings:)
                  .start(room, ahead: aheads, rates:, next_in: 10)
    end

    def ahead(minutes, strategy = :comfort, started: nil)
        Ahead.new(minutes:, band: WAKE, strategy:, started:)
    end

    def room
        Room.new(zone: "red", band: NIGHT, strategy: :comfort,
                 radiators: [valve], aircons: [unit], measured: 16.5,
                 outside: 2.0)
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
