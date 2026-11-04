# frozen_string_literal: true

require "test_helper"

# Devices of one class on different energies: each heats by its own
# energy, whatever their order; one on an energy excluded now goes to
# its least, the others heat.
class PlanMixedTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    ELECTRIC = RADIATOR_CAPS.with(energy: "electricity")

    def test_an_excluded_radiator_rests_the_others_heat_in_any_order
        expected = { "valve:gas" => 20.0, "valve:electric" => 5.0 }
        [%w[gas electric], %w[electric gas]].each do |order|
            result = plan(order)
            assert_equal expected, targets(result), order.join(" first, ")
            assert_empty result.warnings
        end
    end

    private

    def plan(order)
        room = Room.new(zone: "hall", band: BAND, strategy: :comfort,
                        radiators: order.map { radiator(it) }, aircons: [],
                        measured: 18.0, excluded: %w[electricity])
        Plan.new([room]).run
    end

    def targets(result)
        result.actions.select { it.setting == :target }
              .to_h { [it.device, it.to] }
    end

    def radiator(energy)
        Radiator.new(ref: energy, label: "valve:#{energy}",
                     caps: energy == "gas" ? RADIATOR_CAPS : ELECTRIC,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5)
    end
end
