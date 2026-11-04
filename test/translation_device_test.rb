# frozen_string_literal: true

require "test_helper"

# The translation is asked of each device, not of its class: two
# radiators of one room read through their own sensors' gaps.
class TranslationDeviceTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # Each radiator's own sensor reads its own gap above the room.
    class PerDevice < AsIs
        GAPS = { "valve:a" => 0.5, "valve:b" => 1.5 }.freeze

        def target(_room, device, setpoint, _mode = nil)
            gap = GAPS.fetch(device.label)
            Thermidor::Planner::Target.new(celsius: setpoint + gap, gap:)
        end
    end

    def test_each_radiator_gets_its_own_gap
        room = Room.new(zone: "hall", band: BAND, strategy: :quick,
                        radiators: [valve("a"), valve("b")], aircons: [],
                        measured: 18.0)
        actions = Plan.new([room], translation: PerDevice.new).run.actions
        assert_equal({ "valve:a" => [20.5, 0.5], "valve:b" => [21.5, 1.5] },
                     actions.to_h { [it.device, [it.to, it.offset]] })
    end

    private

    def valve(name)
        Radiator.new(ref: name, label: "valve:#{name}", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
