# frozen_string_literal: true

require "test_helper"

# Drifts: a device holding other than what the plan last set it to, and
# the band that holds it for the room.
class DriftsTest < Minitest::Test
    include Thermidor::Planner

    Setpoint = Thermidor::Schedule::Setpoint
    # What was last set of a device setting, as a caller keeps it.
    Row = Data.define(:at, :setting, :from, :to, :offset)
    AT = Time.new(2026, 11, 4, 11, 6)

    def test_a_target_changed_outside_is_found
        found = Drifts.of([room(target: 22.0)], set_to("20.5"))
        seen = found.map { [it.device, it.setting, it.applied, it.now] }
        assert_equal [["valve:VA1", :target, "20.5", "22.0"]], seen
        assert_equal "bedroom: valve:VA1 target set to 22.0 °C outside " \
                     "the plan (20.5 °C at 11:06)", found.first.to_s
    end

    # Who set it is the caller's to name.
    def test_the_planner_is_named
        found = Drifts.of([room(target: 22.0)], set_to("20.5"),
                          planner: "climat")
        assert_match(/ outside climat /, found.first.to_s)
    end

    # The plan writes on the device's step, which it holds as written: the
    # same value back is no drift, a tenth off is.
    def test_the_same_value_back_is_none
        assert_empty Drifts.of([room(target: 20.5)], set_to("20.5"))
        refute_empty Drifts.of([room(target: 20.6)], set_to("20.5"))
    end

    def test_never_set_or_unread_is_none
        assert_empty Drifts.of([room(target: 22.0)], {})
        assert_empty Drifts.of([room(target: nil)], set_to("20.5"))
    end

    def test_switched_off_is_found
        found = Drifts.of([room(mode: :off)], set_to("heat", setting: "mode"))
        assert found.first.off?
        assert_equal Setpoint.new, Drifts.band(found.first, nil)
    end

    # The room's band: the device's value less the offset the plan had
    # added; the other side kept a deadband away.
    def test_the_band_holds_it_for_the_room
        drift = Drifts.of([room(target: 23.0)],
                          set_to("20.5", offset: 0.5)).first
        assert_equal Setpoint.new(heat: 22.5, cool: 23.5),
                     Drifts.band(drift, Setpoint.new(heat: 20, cool: 23))
        cooling = drift.with(mode: :cool, now: "21.0", offset: -0.5)
        assert_equal Setpoint.new(heat: 20.0, cool: 21.5),
                     Drifts.band(cooling, Setpoint.new(heat: 20, cool: 25))
    end

    # Switched on, or a setpoint in fan: no band holds it.
    def test_no_band_for_a_drift_neither_off_nor_a_band
        drift = Drifts.of([room(target: 23.0)], set_to("20.5")).first
        on = drift.with(setting: :mode, now: "heat")
        assert_nil Drifts.band(on, nil)
        assert_nil Drifts.band(drift.with(mode: :fan), nil)
    end

    # A unit unread (its controller out of reach, say): its nil
    # on is not a change from any row, so no drift, nor a false one.
    def test_an_unread_unit_is_no_drift
        unit = aircon(3).with(on: nil, mode: nil, setpoint: nil)
        last = row("unit:3", "power", "true", AT)
        assert_empty Drifts.of([room_with(unit, "living")], last)
    end

    # A setpoint set on a unit that is off leaves it off (tried on the
    # house): no hand on the room, no drift.
    def test_an_off_unit_s_setpoint_is_no_drift
        unit = aircon(3).with(on: false, setpoint: 23.0)
        last = row("unit:3", "setpoint", "21.0", AT)
        assert_empty Drifts.of([room_with(unit, "living")], last)
    end

    # The plan switched the system to cool after setting living's unit to
    # 21 °C for heat: the unit now reports its cool setpoint, 26 °C,
    # which is no change of its own.
    def test_a_mode_the_plan_set_does_not_make_a_unit_drift
        master = aircon(1).with(mode: :cool)
        living = aircon(3).with(mode: :cool, setpoint: 26.0)
        rooms = [room_with(master, "office"), room_with(living, "living")]
        last = row("unit:3", "setpoint", "21.0", AT).merge(
            row("h:1", "mode", "cool", AT + 60, from: "heat")
        )
        assert_empty Drifts.of(rooms, last)
    end

    private

    def room(target: 20.5, mode: :heat)
        radiator = Radiator.new(ref: "VA1", label: "valve:VA1", caps: nil,
                                temperature: nil, mode:, target:,
                                range: 5.0..25.0, step: 0.5)
        Room.new(zone: "bedroom", band: nil, strategy: :quick,
                 radiators: [radiator], aircons: [])
    end

    # What the plan last set VA1's setting to.
    def set_to(to, setting: "target", offset: nil)
        { ["valve:VA1", setting] =>
              Row.new(at: AT, setting:, from: nil, to:, offset:) }
    end

    def aircon(id)
        Aircon.new(ref: "h:1:#{id}", label: "unit:#{id}", caps: nil,
                   system: "h:1", source: "pump", master: id == 1,
                   temperature: nil, on: true, mode: :heat, setpoint: 21.0,
                   range: 15.0..30.0, step: 0.5)
    end

    def room_with(unit, zone)
        Room.new(zone:, band: nil, strategy: :quick, radiators: [],
                 aircons: [unit])
    end

    def row(device, setting, to, at, from: nil)
        { [device, setting] =>
              Row.new(at:, setting:, from:, to:, offset: nil) }
    end
end
