# frozen_string_literal: true

require "test_helper"

# A unit whose caps say it cannot cool (heats only) is given nothing to
# cool, and its room does not vote cool through it.
class CoolCapsTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 24)

    HEAT_ONLY = Caps.new(heat: true, cool: false, quiet: false,
                         energy: "electricity", propagation: %w[forced])

    # The pump cooling for guest: office's heat-only unit, on, is
    # switched off rather than given the cool side.
    def test_a_unit_that_cannot_cool_is_off_when_cooling
        office = room("office", 26.0, unit(1, HEAT_ONLY, on: true))
        guest = room("guest", 26.0, unit(2, AIRCON_CAPS, on: true))
        result = plan(office, guest)
        assert_includes changes(result, "h:1"), %i[mode heat cool]
        assert_equal [[:power, true, false]], changes(result, "unit:1")
        assert_includes changes(result, "unit:2"), [:setpoint, nil, 24.0]
    end

    # office, hot, has only a heat-only unit: the pump is not turned to
    # cool for it.
    def test_a_room_does_not_vote_cool_through_a_unit_that_cannot_cool
        office = room("office", 26.0, unit(1, HEAT_ONLY))
        result = plan(office)
        assert_empty changes(result, "h:1")
        assert_empty result.warnings
    end

    # The pump cooling within its least run: the heat-only unit is
    # switched off all the same, not kept on.
    def test_a_unit_that_cannot_cool_is_not_kept_on_by_min_on
        office = room("office", 26.0, unit(1, HEAT_ONLY, on: true,
                                                         mode: :cool))
        guest = room("guest", 26.0, unit(2, AIRCON_CAPS, on: true,
                                                         mode: :cool))
        settings = StrategySettings.new(pump: PumpSettings.new(min_on: 15))
        pumps = { "pump" => PumpState.new(running: true, switched_ago: 5) }
        result = Plan.new([office, guest], settings:, pumps:).run
        assert_equal [[:power, true, false]], changes(result, "unit:1")
    end

    private

    def room(zone, temperature, unit)
        Room.new(zone:, band: BAND, strategy: :quick, radiators: [],
                 aircons: [unit], measured: temperature)
    end

    def unit(id, caps, on: false, mode: :heat)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps:, system: "h:1",
                   source: "pump", master: id == 1, temperature: nil, on:,
                   mode:, setpoint: 19.0, range: 15.0..30.0, step: 0.5)
    end
end
