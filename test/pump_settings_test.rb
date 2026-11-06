# frozen_string_literal: true

require "test_helper"

# How a heat pump changes direction (PumpSettings): heat on a tie by
# default; with hysteresis, a room asks for the other direction only
# once it is a margin past its band, and a tie keeps the pump as it is.
# The rooms' units are on, the pump running (HuntFixesTest has it
# stopped).
class PumpSettingsTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    HYSTERESIS = StrategySettings.new(
        pump: PumpSettings.new(switch: :hysteresis, margin: 0.5)
    )

    def test_by_default_heat_wins_a_tie
        assert_equal [%i[mode cool heat]],
                     mode_changes(plan(cooling(19.9), cooling(26.5)))
    end

    def test_with_hysteresis_a_tie_keeps_the_direction
        result = plan(cooling(19.0), cooling(26.5), pump: HYSTERESIS)
        assert_empty mode_changes(result)
        assert_includes result.warnings, "r1: needs heat, but pump cool"
    end

    # The pump cooling, the one room a tenth under its band: by default
    # it turns to heat; with hysteresis only once 0.5 °C under.
    def test_with_hysteresis_a_room_must_be_past_the_margin
        assert_equal [%i[mode cool heat]], mode_changes(plan(cooling(19.9)))
        near = plan(cooling(19.9), pump: HYSTERESIS)
        assert_empty mode_changes(near)
        assert_equal ["r1: needs heat, but pump cool"], near.warnings
        assert_equal [%i[mode cool heat]],
                     mode_changes(plan(cooling(19.4), pump: HYSTERESIS))
    end

    # No margin for the direction the pump runs already.
    def test_no_margin_for_the_direction_it_runs
        result = plan(in_mode(:heat), pump: HYSTERESIS)
        assert_empty mode_changes(result)
        assert_includes changes(result, "unit:1"), [:setpoint, 24.0, 20.0]
    end

    # Nor from off: a stopped pump is free to go either way.
    def test_no_margin_from_off
        assert_equal [%i[mode stop heat]],
                     mode_changes(plan(in_mode(:stop), pump: HYSTERESIS))
    end

    def test_an_unknown_switch_or_a_negative_margin_is_refused
        assert_raises(ArgumentError) { PumpSettings.new(switch: :coin) }
        assert_raises(ArgumentError) { PumpSettings.new(margin: -0.1) }
    end

    private

    def plan(*rooms, pump: StrategySettings.new)
        Plan.new(rooms.each_with_index.map do |room, i|
            room.with(zone: "r#{i + 1}", aircons: room.aircons.map do |unit|
                unit.with(label: "unit:#{i + 1}", master: i.zero?)
            end)
        end, settings: pump).run
    end

    def mode_changes(result)
        result.actions.select { it.setting == :mode }
              .map { [it.setting, it.from, it.to] }
    end

    # A room a tenth under its band, its unit in mode.
    def in_mode(mode)
        room = cooling(19.9)
        room.with(aircons: room.aircons.map { it.with(mode:) })
    end

    def cooling(temperature)
        unit = Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                          system: "h:1", source: "pump", master: true,
                          temperature: nil, on: true, mode: :cool,
                          setpoint: 24.0, range: 15.0..30.0, step: 0.5)
        Room.new(zone: "r", band: BAND, strategy: :quick, radiators: [],
                 aircons: [unit], measured: temperature)
    end
end
