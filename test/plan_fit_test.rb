# frozen_string_literal: true

require "test_helper"

# Targets on each device's step and range, left alone within a step:
# the planner on rooms given by hand, as PlanTest's.
class PlanFitTest < Minitest::Test
    include Thermidor::Planner
    include PlanActions

    Setpoint = Thermidor::Schedule::Setpoint
    BAND = Setpoint.new(heat: 20, cool: 24)

    # A target within one step of what the device holds stays: a
    # translation moving by a little does not make it move.
    def test_a_target_moves_by_a_step_or_not_at_all
        near = room("bedroom", 18.0, radiator: :heat)
        held = near.with(radiators: [radiator(:heat).with(target: 19.7)])
        assert_empty changes(plan(held), "valve:VA1")
        far = near.with(radiators: [radiator(:heat).with(target: 19.4)])
        assert_equal [[:target, 19.4, 20.0]], changes(plan(far), "valve:VA1")
    end

    # Cooling, a unit takes its cooling setpoints, not those of the
    # heating it is still in.
    def test_cooling_fits_the_cooling_range
        unit = aircon(1, 30.0).with(range: 15.0..25.0,
                                    ranges: { heat: 15.0..25.0,
                                              cool: 18.0..32.0 })
        hot = Room.new(zone: "office", band: Setpoint.new(heat: 20, cool: 27),
                       strategy: :quick, radiators: [], aircons: [unit])
        assert_equal [[:power, false, true], [:setpoint, nil, 27.0]],
                     changes(plan(hot), "unit:1")
    end

    private

    def room(zone, temperature, aircon: nil, radiator: nil,
             strategy: :quick)
        Room.new(zone:, band: BAND, strategy:,
                 radiators: radiator ? [radiator(radiator)] : [],
                 aircons: aircon ? [aircon(aircon, temperature)] : [])
    end

    def radiator(mode)
        Radiator.new(ref: "VA1", label: "valve:VA1", caps: RADIATOR_CAPS,
                     temperature: nil, mode:, target: 17.0, range: 5.0..25.0,
                     step: 0.5, least: 5.0)
    end

    def aircon(id, temperature)
        Aircon.new(ref: "h:1:#{id}", label: "unit:#{id}",
                   caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: id == 1, temperature:,
                   on: false, mode: :heat, setpoint: 19.0, range: 15.0..30.0,
                   step: 0.5)
    end
end
