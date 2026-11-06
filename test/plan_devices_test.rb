# frozen_string_literal: true

require "test_helper"

# The plan with devices ranked one by one: each device's own target, a
# unit that cannot go as low as the band left off, a heat pump voted for
# by the units on it.
class PlanDevicesTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    LOUD = RADIATOR_CAPS.with(quiet: false)

    # quiet, a quiet and a loud radiator: the quiet one heats, the loud
    # one rests, in either order, unwarned.
    def test_quiet_heats_with_the_quiet_radiator_alone
        valves = [valve("q", RADIATOR_CAPS), valve("l", LOUD)]
        [valves, valves.reverse].each do |order|
            result = plan(room(:quiet, radiators: order))
            assert_equal({ "valve:q" => 20.0, "valve:l" => 5.0 },
                         targets(result))
            assert_empty result.warnings
        end
    end

    # An away band of 16 °C: the unit that goes down to 10 °C holds it,
    # the one whose least is 18 °C is switched off, not set above the
    # band.
    def test_a_unit_that_cannot_go_as_low_as_the_band_is_switched_off
        away = Thermidor::Schedule::Setpoint.new(heat: 16, cool: 30)
        low  = unit(1, ranges: { heat: 10.0..25.0, cool: 18.0..30.0 })
        high = unit(2, ranges: { heat: 18.0..30.0, cool: 18.0..30.0 })
        result = plan(room(:quick, aircons: [low, high]).with(band: away,
                                                              measured: 15.0))
        assert_includes changes(result, "unit:1"), [:setpoint, nil, 16.0]
        assert_equal [[:power, true, false]], changes(result, "unit:2")
    end

    # living needs heat; its loud unit on pump a may not heat it under
    # quiet, its quiet unit on pump b may: pump b heats, pump a is left
    # to office's cooling.
    def test_a_room_votes_for_a_heat_pump_only_by_a_unit_that_heats
        quiet  = AIRCON_CAPS.with(quiet: true)
        living = room(:quiet, aircons: [unit(1, on: "a"),
                                        unit(2, on: "b", caps: quiet)])
        office = room(:quick, aircons: [unit(3, on: "a", master: false)])
                 .with(zone: "office", measured: 27.0)
        result = plan(living, office)
        assert_empty changes(result, "a:1")
        assert_equal [%i[mode cool heat]], changes(result, "b:1")
    end

    private

    def room(strategy, radiators: [], aircons: [])
        Room.new(zone: "living", band: BAND, strategy:, radiators:,
                 aircons:, measured: 18.0)
    end

    def targets(result)
        result.actions.select { it.setting == :target }
              .to_h { [it.device, it.to] }
    end

    def valve(name, caps)
        Radiator.new(ref: name, label: "valve:#{name}", caps:,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end

    # Unit id of system ON:1 on heat pump pump-ON, its master unless said.
    def unit(id, on: "h", caps: AIRCON_CAPS, **fields)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps:,
                   system: "#{on}:1", source: "pump-#{on}", master: true,
                   temperature: nil, on: true, mode: :cool, setpoint: 24.0,
                   range: 18.0..30.0, step: 0.5, **fields)
    end
end
