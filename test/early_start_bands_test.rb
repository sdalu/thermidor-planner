# frozen_string_literal: true

require "test_helper"

# Early start's bands (EarlyStart#start): the latch holding a warm-up
# started, an unread room, the sides that move, the change driving among
# several, and cooling.
class EarlyStartBandsTest < Minitest::Test
    include Thermidor::Planner

    S = Thermidor::Schedule
    NIGHT = S::Setpoint.new(heat: 17, cool: 27)
    WAKE  = S::Setpoint.new(heat: 20, cool: 25)
    RADIATORS = Rise.new(base: 3.0, loss: 0.08, delay: 15)
    BOTH = Rise.new(base: 6.0, loss: 0.08, delay: 5)
    RATES = { heat: { radiators: RADIATORS, both: BOTH } }.freeze

    # The latch: once started, it goes on past its aim, rule 2 or not.
    def test_a_started_warm_up_goes_on
        warm = room.with(measured: 19.9)
        kept = start(warm, ahead(30, started: :comfort))
        assert_equal "+20.0..+25.0", kept.band.to_s
        assert_equal :comfort, kept.strategy
    end

    # A room overshooting past the middle of the band ahead keeps it:
    # the latch holds every side asking more, not the nearer one.
    def test_a_started_warm_up_holds_past_mid_band
        bands = [22.4, 22.6].map do |temperature|
            start(room.with(measured: temperature),
                  ahead(40, started: :comfort)).band.to_s
        end
        assert_equal ["+20.0..+25.0"] * 2, bands
    end

    # Held without a rate, it says nothing it does not do.
    def test_a_held_side_without_a_rate_says_nothing
        held = start(room.with(measured: 22.6), ahead(40, started: :comfort))
        assert_empty held.notes
    end

    def test_a_started_warm_up_goes_on_unread_and_unrated
        unread = room.with(measured: nil, radiators: [valve(nil, nil)])
        kept = start(unread, ahead(100, started: :comfort))
        assert kept.ahead
        assert_equal [:early_unread], kept.notes.map(&:kind)
        assert start(room, ahead(100, started: :comfort), rates: {}).ahead
    end

    def test_an_unread_room_starts_nothing
        unread = room.with(measured: nil, radiators: [valve(nil, nil)])
        found = start(unread, ahead(100))
        assert_nil found.ahead
        assert_equal ["red: no early start for +20.0: room temperature " \
                      "unknown"], found.notes
    end

    # Only a side asking more moves: a heat side ahead higher, the cool
    # side kept the band now's.
    def test_only_the_side_asking_more_moves
        assert_equal "+20.0..+27.0", start(room, ahead(130)).band.to_s
    end

    # Sides closer than the deadband take the band ahead whole.
    def test_the_deadband_takes_the_band_ahead_whole
        near = room.with(band: S::Setpoint.new(heat: 17, cool: 20.5))
        hot = ahead(130, band: S::Setpoint.new(heat: 20, cool: 26))
        assert_equal "+20.0..+26.0", start(near, hot).band.to_s
    end

    # Two changes close: the higher heat side drives, its strategy and
    # Ahead.
    def test_the_highest_heat_side_drives
        first = ahead(100, band: S::Setpoint.new(heat: 19, cool: 27),
                           strategy: :quiet)
        second = ahead(135)
        found = start(room, first, second)
        assert_equal second, found.ahead
        assert_equal :comfort, found.strategy
        assert_equal 20.0, found.band.heat
    end

    def test_cooling_mirrors_heating
        hot = room.with(measured: 27.5, aircons: [unit], radiators: [])
        rates = { cool: { units: Rise.new(base: 2.0) } }
        cool = ahead(70, band: S::Setpoint.new(heat: 17, cool: 24))
        found = start(hot, cool, rates:)
        assert_equal "+17.0..+24.0", found.band.to_s
        assert_in_delta 99.0, found.minutes, 0.01
    end

    private

    def start(room, *aheads, rates: RATES, settings: EarlyStartSettings.new)
        EarlyStart.new(settings:)
                  .start(room, ahead: aheads, rates:, next_in: 10)
    end

    def ahead(minutes, band: WAKE, strategy: :comfort, started: nil)
        Ahead.new(minutes:, band:, strategy:, started:)
    end

    def room
        Room.new(zone: "red", band: NIGHT, strategy: :comfort,
                 radiators: [valve], aircons: [], measured: 16.5,
                 outside: 2.0)
    end

    def valve(mode = :heat, temperature = 16.5)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature:, mode:, target: 17.0,
                     range: 5.0..25.0, step: 0.5)
    end

    def unit
        Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "system:1", source: "pump", master: true,
                   temperature: 16.5, on: false, mode: :heat,
                   setpoint: 22.0, range: 18.0..30.0, step: 0.5)
    end
end
