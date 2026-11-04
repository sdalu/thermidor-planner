# frozen_string_literal: true

require "test_helper"

# A unit that could not be read never stands for its system: the
# system's mode is read on a unit that was, so the plan and the drifts
# are those of a house without the unread one.
class UnreadSystemTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    Row = Data.define(:at, :setting, :from, :to, :offset)

    # living, at 22 °C in its band, its unit heating: nothing to do,
    # whether office's unread unit is the master or not.
    def test_an_unread_unit_does_not_stand_for_its_system
        alone = plan([living])
        [true, false].each do |master|
            assert_equal alone.actions, plan([office(master:), living]).actions
        end
    end

    # living needing heat on a system heating already: no mode written.
    def test_no_mode_is_written_from_an_unread_unit
        cold = living.with(measured: 18.0)
        actions = plan([office(master: true), cold]).actions
        assert_empty(actions.select { it.setting == :mode })
    end

    # The system set to heat outside, where cool was last set: found
    # whether office's unread unit is listed or not.
    def test_an_unread_unit_hides_no_mode_drift
        last = { ["h:1", "mode"] => Row.new(at: Time.new(2026, 11, 4, 8),
                                            setting: "mode", from: "heat",
                                            to: "cool", offset: nil) }
        assert_equal 1, Drifts.of([living], last).size
        assert_equal 1, Drifts.of([office(master: true), living], last).size
    end

    private

    def plan(rooms) = Plan.new(rooms).run

    def living
        unit = Aircon.new(ref: "h:1:2", label: "unit:living",
                          caps: AIRCON_CAPS, system: "h:1", source: "pump",
                          master: false, temperature: 22.0, on: true,
                          mode: :heat, setpoint: 20.0, range: 16.0..30.0,
                          step: 0.5)
        Room.new(zone: "living", band: BAND, strategy: :comfort,
                 radiators: [], aircons: [unit], measured: 22.0)
    end

    def office(master:)
        unit = Aircon.new(ref: "h:1:1", label: "unit:office",
                          caps: AIRCON_CAPS, system: "h:1", source: "pump",
                          master:, temperature: nil, on: nil, mode: nil,
                          setpoint: nil, range: nil, step: nil)
        Room.new(zone: "office", band: BAND, strategy: :comfort,
                 radiators: [], aircons: [unit])
    end
end
