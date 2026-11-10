# frozen_string_literal: true

require "test_helper"

# Early start (EarlyStart, design/early-start.md): a change begun ahead
# of its time so the room is in the band at it, judged without a clock
# from the minutes until the change and until the next plan, and the
# rates the caller learned.
class EarlyStartTest < Minitest::Test
    include Thermidor::Planner

    S = Thermidor::Schedule
    NIGHT = S::Setpoint.new(heat: 17, cool: 27)
    WAKE  = S::Setpoint.new(heat: 20, cool: 25)
    # The design's worked case: radiators at 3.0 °C/h, losing 0.08 an
    # hour a degree, 15 min before the room moves.
    RADIATORS = Rise.new(base: 3.0, loss: 0.08, delay: 15)
    BOTH = Rise.new(base: 6.0, loss: 0.08, delay: 5)
    RATES = { heat: { radiators: RADIATORS, both: BOTH } }.freeze

    # red-room at 05:00, 16.5 °C, 2.0 °C outside, 07:30=wakeup: 131 min
    # to 19.8, so not yet at 150 min, due at 140.
    def test_the_worked_case
        assert_nil start(room, ahead(150)).ahead
        due = start(room, ahead(140))
        assert_equal "+20.0..+25.0", due.band.to_s
        assert_equal :comfort, due.strategy
        assert_in_delta 131.2, due.minutes, 0.1
    end

    def test_the_worked_case_said
        due = start(room, ahead(140))
        assert_equal ["red: early start for +20.0 in 140 min: needs 131 " \
                      "(radiators, 1.8 °C/h)"], due.notes
        assert_equal [:early_start], due.notes.map(&:kind)
    end

    def test_without_loss_the_rise_is_linear
        rates = { heat: { radiators: Rise.new(base: 2.0) } }
        assert_in_delta 99.0, start(room, ahead(100), rates:).minutes, 0.01
    end

    def test_the_learned_gap_stands_for_an_outside_not_known
        rates = { heat: { radiators: RADIATORS.with(gap: 14.5) } }
        unknown = room.with(outside: nil)
        assert_in_delta 131.2, start(unknown, ahead(140), rates:).minutes, 0.1
    end

    def test_the_delay_is_added
        rates = { heat: { radiators: RADIATORS.with(delay: 0.0) } }
        assert_in_delta 116.2, start(room, ahead(120), rates:).minutes, 0.1
    end

    # Settling at 14.5 °C, the radiators never bring it to 19.8: started
    # lead ahead, said.
    def test_out_of_reach_starts_lead_ahead
        rates = { heat: { radiators: Rise.new(base: 1.0, loss: 0.08) } }
        assert_nil start(room, ahead(200), rates:).ahead
        due = start(room, ahead(185), rates:)
        assert due.ahead
        assert_equal [:early_unreachable], due.notes.map(&:kind)
    end

    def test_a_long_warm_up_is_capped_at_lead
        rates = { heat: { radiators: Rise.new(base: 1.0) } }
        assert_nil start(room, ahead(195), rates:).ahead
        due = start(room, ahead(188), rates:)
        assert_in_delta 198.0, due.minutes, 0.01
        assert_equal %i[early_start early_late early_capped],
                     due.notes.map(&:kind)
    end

    def test_too_late_it_starts_now_and_says_so
        due = start(room, ahead(60))
        assert due.ahead
        assert_includes due.notes.map(&:to_s),
                        "red: early start for +20.0 late: needs 131 min, " \
                        "60 left"
    end

    # A lower band ahead, or a room in the band ahead already, does not
    # move.
    def test_a_lower_band_or_a_warm_room_starts_nothing
        night = ahead(30, band: S::Setpoint.new(heat: 16, cool: 27))
        assert_nil start(room, night).ahead
        warm = start(room.with(measured: 19.9), ahead(30))
        assert_nil warm.ahead
        assert_empty warm.notes
    end

    def test_validation
        assert_raises(ArgumentError) { EarlyStartSettings.new(lead: 0) }
        assert_raises(ArgumentError) { EarlyStartSettings.new(hurry: "on") }
        assert_raises(ArgumentError) { EarlyStartSettings.new(reach: -1) }
        assert_raises(ArgumentError) { Rise.new(base: 0) }
        assert_raises(ArgumentError) { Rise.new(base: 1, loss: -1) }
        assert_raises(ArgumentError) { ahead(-1) }
        assert_raises(ArgumentError) do
            EarlyStart.new.start(room, ahead: [], rates: RATES, next_in: 0)
        end
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
