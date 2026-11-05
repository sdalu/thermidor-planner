# frozen_string_literal: true

require "test_helper"

# A raise lifts a room's heat side only through a device taking part:
# read, able to heat, on an energy not excluded now.
class RoomLiftTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    RAISE = Effects.new(preferred: [], avoided: [], caps: {},
                        raises: { "electricity" => 1.5 })

    def test_a_raise_lifts_through_a_unit_taking_part
        assert_in_delta 1.5, room(unit).lift
        assert_equal :heat, room(unit).need
    end

    def test_an_excluded_energy_lifts_nothing
        excluded = room(unit).with(excluded: %w[electricity])
        assert_in_delta 0.0, excluded.lift
        assert_nil excluded.need
    end

    def test_an_unread_unit_lifts_nothing
        assert_in_delta 0.0, room(unit.with(mode: nil)).lift
    end

    def test_a_unit_that_cannot_heat_lifts_nothing
        cool_only = AIRCON_CAPS.with(heat: false)
        assert_in_delta 0.0, room(unit.with(caps: cool_only)).lift
    end

    private

    def room(unit)
        Room.new(zone: "office", band: BAND, strategy: :quick, radiators: [],
                 aircons: [unit], effects: RAISE, measured: 21.0)
    end

    def unit
        Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on: false, mode: :heat, setpoint: 20.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
