# frozen_string_literal: true

require "test_helper"

# A system found in stop, dry or auto, with and without a direction to
# give; one set aside; a heat pump held to heat, to cool, or to
# neither (pumps:).
class PlanModesTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # Needing heat or cool, the system goes the pump's direction from
    # any of these modes, and the unit gets that mode's setpoint.
    def test_stop_dry_and_auto_take_the_pump_s_direction
        %i[stop dry auto].each do |mode|
            assert_equal [["h:1", :mode, mode, :heat],
                          ["unit:1", :setpoint, nil, 20.0]],
                         actions(plan(18.0, mode)), mode.to_s
            assert_equal [["h:1", :mode, mode, :cool],
                          ["unit:1", :setpoint, nil, 26.0]],
                         actions(plan(28.0, mode)), mode.to_s
        end
    end

    # No direction: a unit in stop is switched off; dry and auto run
    # without the heat pump and are left running, auto said.
    def test_without_a_direction_only_stop_is_switched_off
        assert_equal [["unit:1", :power, true, false]],
                     actions(plan(22.0, :stop))
        assert_empty plan(22.0, :dry).actions
        auto = plan(22.0, :auto)
        assert_empty auto.actions
        assert_equal ["h:1: left in auto: the heat pump pump has no " \
                      "direction now"], auto.warnings
    end

    # Set aside in dry, the room needing heat: nothing is set.
    def test_a_system_set_aside_in_dry_is_left
        result = plan(18.0, :dry, aside: %w[h:1])
        assert_empty result.actions
        assert_empty result.warnings
    end

    def test_a_pump_held_to_heat
        assert_equal [["unit:1", :setpoint, 22.0, 20.0]],
                     actions(plan(18.0, held: :heat))
        hot = plan(28.0, held: :heat)
        assert_equal [["unit:1", :power, true, false]], actions(hot)
        assert_equal ["office: needs cool, but pump heat"], hot.warnings
    end

    def test_a_pump_held_to_cool
        cold = plan(18.0, held: :cool)
        assert_equal [["h:1", :mode, :heat, :cool],
                      ["unit:1", :power, true, false]], actions(cold)
        assert_equal ["office: needs heat, but pump cool"], cold.warnings
        assert_equal [["h:1", :mode, :heat, :cool],
                      ["unit:1", :setpoint, nil, 26.0]],
                     actions(plan(28.0, held: :cool))
    end

    # Held to neither: the unit is off, the mode left, the room said.
    def test_a_pump_held_to_neither
        { 18.0 => "heat", 28.0 => "cool" }.each do |temperature, need|
            result = plan(temperature, held: nil)
            assert_equal [["unit:1", :power, true, false]], actions(result)
            assert_equal ["office: needs #{need}, but pump stays off"],
                         result.warnings
        end
    end

    private

    # office at temperature, its one unit on in mode; held: the pump's
    # held direction, when given.
    def plan(temperature, mode = :heat, aside: [], **held)
        pumps = held.empty? ? {} : { "pump" => PumpState.new(**held) }
        room = Room.new(zone: "office", band: BAND, strategy: :quick,
                        radiators: [], aircons: [unit(mode)],
                        measured: temperature)
        Plan.new([room], pumps:, aside:).run
    end

    def actions(result)
        result.actions.map { [it.device, it.setting, it.from, it.to] }
    end

    def unit(mode)
        Aircon.new(ref: "1", label: "unit:1", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on: true, mode:, setpoint: 22.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
