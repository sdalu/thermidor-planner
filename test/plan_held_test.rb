# frozen_string_literal: true

require "test_helper"

# Devices held on by hand (room.held): the room's others kept a deadband
# away, so a radiator and an aircon never fight; one working past the
# band said.
class PlanHeldTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    Setpoint = Thermidor::Schedule::Setpoint
    BAND = Setpoint.new(heat: 20, cool: 24)

    # A translation for which a radiator's sensor reads 0.8 °C above the
    # room while heating, and a unit's as the room.
    class Warmer < AsIs
        def target(room, device, setpoint, mode = nil)
            return super unless device.is_a?(Thermidor::Planner::Radiator)
            Thermidor::Planner::Target.new(celsius: setpoint + 0.8, gap: 0.8)
        end
    end

    # A valve held on by hand at 25 °C: the room's unit cools no lower
    # than 26 °C, a degree above, so the two never fight.
    def test_a_unit_cools_a_degree_above_a_valve_held_heating
        valve = Radiator.new(ref: "VA1", label: "valve:VA1", caps: nil,
                             temperature: nil, mode: :heat, target: 25.0,
                             range: 5.0..25.0, step: 0.5)
        cooling = unit(1).with(on: true, mode: :cool, setpoint: 24.0,
                               range: 18.0..32.0)
        hot = room("office", 27.0, [cooling]).with(held: [valve])
        assert_includes changes(plan(hot), "unit:1"), [:setpoint, 24.0, 26.0]
    end

    # A unit held on by hand cooling at 22 °C: the room's valves heat no
    # higher than 21 °C.
    def test_valves_heat_a_degree_below_a_unit_held_cooling
        cold = room("office", 18.0, []).with(
            radiators: [valve_at(17.0)],
            held: [unit(1).with(on: true, mode: :cool, setpoint: 22.0)]
        ).with(band: Setpoint.new(heat: 23, cool: 26))
        assert_includes changes(plan(cold), "valve:VA1"), [:target, 17.0, 21.0]
    end

    # A unit held on heating at 26 °C where the band cools above 24 °C:
    # left alone, but said.
    def test_a_device_held_against_the_band_is_said
        hot = room("office", 27.0, []).with(
            held: [unit(2).with(on: true, mode: :heat, setpoint: 26.0)]
        )
        assert_includes plan(hot).warnings,
                        "office: unit:2 left on, heating to 26.0 °C, " \
                        "above the band's cool side 24.0 °C"
    end

    # A valve held heating at 25.8 °C on its own sensor, the translation
    # saying its sensor reads 0.8 °C above the room while heating: in
    # room terms it heats to 25 °C, the same as the valve
    # above, so the room's unit cools no lower than 26 °C, not 26.8 °C
    # (the valve's own 25.8 plus the deadband, judged apart).
    def test_a_held_device_is_judged_in_room_not_own_sensor_terms
        valve = Radiator.new(ref: "VA1", label: "valve:VA1", caps: nil,
                             temperature: nil, mode: :heat, target: 25.8,
                             range: 5.0..26.0, step: 0.5)
        cooling = unit(1).with(on: true, mode: :cool, setpoint: 24.0,
                               range: 18.0..32.0)
        hot = room("office", 27.0, [cooling]).with(held: [valve])
        found = Plan.new([hot], translation: Warmer.new).run
        assert_includes changes(found, "unit:1"), [:setpoint, 24.0, 26.0]
    end

    # A unit held heating by hand while the room's others flip the pump
    # to cool: left alone (no action writes it), but said, so the hand
    # is not silently overridden.
    def test_a_unit_held_heating_is_said_when_the_pump_goes_cooling
        office = room("office", 18.0, []).with(
            held: [unit(1).with(on: true, mode: :heat, setpoint: 20.0)]
        )
        guest = room("guest", 27.0, [unit(2).with(on: true, mode: :cool)])
        assert_includes plan(office, guest).warnings,
                        "office: unit:1 held heating, the heat pump " \
                        "goes cooling"
    end

    private

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

    def valve_at(target)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target:, range: 5.0..25.0,
                     step: 0.5)
    end
end
