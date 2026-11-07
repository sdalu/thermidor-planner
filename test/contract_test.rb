# frozen_string_literal: true

require "test_helper"

# What the planner takes beyond the README's example: a heat pump named
# by any value, a room the schedule gave no band, one with no strategy.
class ContractTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    def test_a_heat_pump_named_by_a_symbol_is_said_by_its_name
        room = Room.new(zone: "office", band: BAND, strategy: :quick,
                        radiators: [], aircons: [unit(:pump)],
                        measured: 18.0)
        mode = Plan.new([room]).run.actions.find { it.setting == :mode }
        assert_equal "source pump", mode.why
    end

    # No band: nothing to hold, so no heating and no cooling, no error.
    def test_a_room_without_a_band_is_left_off
        room = Room.new(zone: "office", band: nil, strategy: :quick,
                        radiators: [], aircons: [unit("pump")],
                        measured: 30.0)
        result = Plan.new([room]).run
        assert_nil room.need
        changes = result.actions.map { [it.setting, it.from, it.to] }
        assert_equal [[:power, true, false]], changes
    end

    # A strategy is a Symbol: none is refused when the room is made,
    # not found later as a crash in the plan.
    def test_a_room_without_a_strategy_is_refused
        error = assert_raises(ArgumentError) do
            Room.new(zone: "office", band: BAND, strategy: nil,
                     radiators: [], aircons: [unit("pump")])
        end
        assert_equal "office: no strategy", error.message
    end

    private

    def unit(source)
        Aircon.new(ref: "1", label: "unit:office", caps: AIRCON_CAPS,
                   system: "h:1", source:, master: true, temperature: nil,
                   on: true, mode: :cool, setpoint: 24.0, range: 16.0..30.0,
                   step: 0.5)
    end
end
