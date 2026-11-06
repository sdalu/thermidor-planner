# frozen_string_literal: true

require "test_helper"

# A unit unread (its controller out of reach, say): kept in its room as
# an Aircon with nil fields, as an unread valve stays a Radiator so. It
# gets no action and does not vote for its
# (otherwise directionless) heat pump; the room's other devices are
# planned as if it were not there.
class PlanUnreadTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    Setpoint = Thermidor::Schedule::Setpoint
    BAND = Setpoint.new(heat: 20, cool: 24)

    def test_an_unread_unit_gets_no_action_and_does_not_vote
        room = Room.new(zone: "salon", band: BAND, strategy: :quick,
                        radiators: [radiator(:off)], aircons: [unread],
                        measured: 18.0)
        result = plan(room)
        assert_empty changes(result, "unit:1")
        assert_empty changes(result, "h:1")
        assert_equal [%i[mode off heat], [:target, 17.0, 20.0]],
                     changes(result, "valve:VA1")
        assert_equal ["salon: unit:1 not read: left as it is"],
                     result.warnings
    end

    # Alone with a radiator able to heat, the room needs heat: without
    # the fix, the unread unit's caps alone would make the air
    # conditioning "able" too, splitting comfort's offset between them.
    def test_the_room_s_other_devices_plan_as_if_it_were_not_there
        with_unit = Room.new(zone: "salon", band: BAND, strategy: :comfort,
                             radiators: [radiator(:heat)], aircons: [unread],
                             measured: 18.0)
        without_unit = with_unit.with(aircons: [])
        assert_equal changes(plan(without_unit), "valve:VA1"),
                     changes(plan(with_unit), "valve:VA1")
    end

    private

    def radiator(mode)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: nil, mode:, target: 17.0, range: 5.0..25.0,
                     step: 0.5, least: 5.0)
    end

    # A unit the caller could not read: on its own heat pump (system
    # h:1), its read fields all nil.
    def unread
        Aircon.new(ref: "h:1:1", label: "unit:1",
                   caps: AIRCON_CAPS,
                   system: "h:1", source: "h:1", master: false,
                   temperature: nil, on: nil, mode: nil, setpoint: nil,
                   range: nil, step: nil)
    end
end
