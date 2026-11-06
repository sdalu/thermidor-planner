# frozen_string_literal: true

require "test_helper"

# A heat pump and the units on it: the direction from the rooms that can
# use it, each pump its own units, a unit's setpoint and range taken for
# the mode it will run in.
class PlanPumpTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    Setpoint = Thermidor::Schedule::Setpoint
    BAND = Setpoint.new(heat: 20, cool: 24)

    # A unit heating at 24 is switched to cool for a hot room: its cool
    # setpoint, which it will then report, is written, though the heat
    # one read now happens to be the target.
    def test_a_mode_change_writes_the_new_mode_s_setpoint
        unit = unit(1).with(on: true, setpoint: 24.0)
        result = plan(room("office", 26.0, [unit]))
        assert_includes changes(result, "unit:1"), [:setpoint, nil, 24.0]
    end

    # A unit cooling now (its range 18..32) heats an away band of 16, by
    # its heating range (10..25), instead of being left out.
    def test_a_unit_cooling_now_heats_by_its_heating_range
        unit = unit(1).with(on: true, mode: :cool, range: 18.0..32.0,
                            ranges: { heat: 10.0..25.0, cool: 18.0..32.0 })
        away = room("office", 15.0, [unit]).with(band: Setpoint.new(heat: 16,
                                                                    cool: 30))
        refute_includes changes(plan(away), "unit:1"), [:power, true, false]
        assert_includes changes(plan(away), "unit:1"), [:setpoint, nil, 16.0]
    end

    # living has a unit on each of two pumps and needs heat; office and
    # guest, on pump b, need cool: pump a heats living, pump b cools.
    def test_a_room_on_two_heat_pumps_sets_each_its_own
        result = two_pumps
        assert_empty changes(result, "a:1")
        assert_equal [%i[mode heat cool]], changes(result, "b:1")
        assert_includes changes(result, "unit:a1"), [:power, false, true]
        assert_empty changes(result, "unit:b1")
    end

    # Rooms whose unit was switched off by hand do not choose the pump's
    # direction: office, the one room a unit runs in, is heated.
    def test_units_held_off_do_not_choose_the_direction
        office = room("office", 18.0, [unit(1).with(on: true, setpoint: 20.0)])
        hot = %w[guest attic].each_with_index.map do |name, i|
            Room.new(zone: name, band: BAND, strategy: :quick, radiators: [],
                     aircons: [], held: [unit(i + 2)], measured: 26.0)
        end
        result = plan(office, *hot)
        assert_empty changes(result, "h:1")
        assert_empty changes(result, "unit:1")
        assert_empty result.warnings
    end

    # A unit found in fan (or dry) with no room needing heat or cool is
    # left running: no direction is no reason to switch it off.
    def test_a_unit_in_fan_is_left_running
        fan = unit(1).with(on: true, mode: :fan, setpoint: nil)
        assert_empty plan(room("office", 22.0, [fan])).actions
    end

    # Whole readings (the Local API sends 21, not 21.0) average to 21.5,
    # not 21.
    def test_the_devices_average_is_not_truncated
        units = [unit(1).with(temperature: 21), unit(2).with(temperature: 22)]
        room = Room.new(zone: "office", band: BAND, strategy: :quick,
                        radiators: [], aircons: units)
        assert_in_delta 21.5, room.temperature
    end

    # office may not heat (electricity excluded), guest needs cool: the
    # pump stays cooling for guest rather than turn to heat for nobody.
    def test_a_room_that_may_not_heat_does_not_turn_the_pump
        cooling = ->(id) { unit(id).with(on: true, mode: :cool) }
        office = room("office", 18.0, [cooling.call(1)])
                 .with(excluded: %w[electricity])
        guest = room("guest", 27.0, [cooling.call(2)])
        result = plan(office, guest)
        assert_empty changes(result, "h:1")
        refute_includes changes(result, "unit:2"), [:power, true, false]
    end

    # The system's master zone bound to no zone: its mode is still set,
    # read from any of its units.
    def test_a_system_whose_master_is_unbound_still_gets_its_mode
        red = unit(2).with(on: true)
        assert_equal [%i[mode heat cool]],
                     changes(plan(room("red", 26.0, [red])), "h:1")
        refute_includes changes(plan(room("red", 22.0, [red])), "unit:2"),
                        [:power, true, false]
    end

    # A unit in aux heats: the pump heating, its mode is not rewritten.
    def test_aux_counts_as_heating
        aux = unit(1).with(on: true, mode: :aux, setpoint: 20.0)
        assert_empty changes(plan(room("office", 18.0, [aux])), "h:1")
    end

    private

    def two_pumps
        on_b = %w[living office guest].each_with_index.map do |_, i|
            unit(i + 1, host: "b", source: "pump-b")
        end
        plan(room("living", 18.0,
                  [unit(1, host: "a", source: "pump-a"), on_b[0]]),
             room("office", 26.0, [on_b[1]]), room("guest", 26.0, [on_b[2]]))
    end

    def room(zone, temperature, aircons)
        Room.new(zone:, band: BAND, strategy: :quick, radiators: [], aircons:,
                 measured: temperature)
    end

    # Unit id of system 1 on host (its label HOST:1), master when id is
    # 1; labelled by host and id when not on h.
    def unit(id, host: "h", source: "pump")
        label = host == "h" ? "unit:#{id}" : "unit:#{host}#{id}"
        Aircon.new(ref: "#{host}:1:#{id}", label:,
                   caps: AIRCON_CAPS, system: "#{host}:1", source:,
                   master: id == 1, temperature: nil, on: false, mode: :heat,
                   setpoint: 19.0, range: 15.0..30.0,
                   step: 0.5)
    end
end
