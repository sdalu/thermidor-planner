# frozen_string_literal: true

require "test_helper"

# A heat pump waiting in its mild gap (PumpWait): stopped, it restarts
# only once its room is mild_deadband under the unit's target, so a
# radiator stepped back behind the unit sits backup_margin under that
# point, a safety net, the pump starting first.
class PumpWaitTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    SOLAR = Effects.none.with(preferred: %w[electricity])
    STOPPED = { "pump" => PumpState.new(running: false, switched_ago: 120) }
              .freeze
    RUNNING = { "pump" => PumpState.new(running: true, switched_ago: 120) }
              .freeze

    # Solar makes the unit the lead, the valve a gap behind at 19.0: on
    # the pump's restart point, it would keep the pump from starting.
    def test_a_stepped_back_radiator_sits_under_the_restart_point
        result = plan(room(19.6), pump)
        assert_equal [["valve:a", 18.5]], targets(result)
        assert_equal ["quick, backup 18.5 while the pump waits, " \
                      "+20.0..+26.0, at 19.6"], result.actions.map(&:why)
    end

    # Under the restart point the pump starts; the comfort gap is back.
    def test_once_the_pump_starts_the_gap_is_the_strategy_s
        result = plan(room(18.9), pump)
        assert_equal [["valve:a", 19.0]], targets(result)
        assert_equal [["unit:a", :power, true]], powers(result)
        assert_equal [["valve:a", 19.0]],
                     targets(plan(room(19.6, on: true), pump, RUNNING))
    end

    def test_off_the_strategy_s_target_stands
        assert_equal [["valve:a", 19.0]],
                     targets(plan(room(19.6), pump(backup_margin: nil)))
    end

    # The radiators leading in mild weather, the unit their backup: the
    # valve is not behind the unit, and is left leading.
    def test_a_radiator_leading_is_left
        led = room(19.6).with(effects: Effects.none)
        assert_equal [["valve:a", 20.0]],
                     targets(plan(led, pump(mild_lead: 10.0)))
    end

    # Solar undoes the mild lead: the lead is not said.
    def test_a_mild_lead_undone_by_an_effect_is_not_said
        result = plan(room(19.6), pump(mild_lead: 10.0))
        assert(result.actions.none? { it.why.include?("pump backup") })
    end

    private

    def pump(**given)
        StrategySettings.new(comfort: 1.0,
                             pump: PumpSettings.new(mild: 6.0, **given))
    end

    def plan(room, settings, pumps = STOPPED)
        Plan.new([room], settings:, pumps:).run
    end

    def targets(result)
        result.actions.select { it.setting == :target }
              .map { [it.device, it.to] }
    end

    def powers(result)
        result.actions.select { it.setting == :power }
              .map { [it.device, it.setting, it.to] }
    end

    # quick, solar preferring electricity, 10.3 °C outside.
    def room(temperature, on: false)
        Room.new(zone: "a", band: BAND, strategy: :quick, aircons: [unit(on)],
                 radiators: [valve], measured: temperature, outside: 10.3,
                 effects: SOLAR)
    end

    def unit(on)
        Aircon.new(ref: "a", label: "unit:a", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on:, mode: :heat, setpoint: 20.0,
                   range: 15.0..30.0, step: 0.5)
    end

    def valve
        Radiator.new(ref: "a", label: "valve:a", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 20.5,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
