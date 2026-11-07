# frozen_string_literal: true

require "test_helper"

# Against a heat pump's short cycles (PumpSettings), judged per pump: its
# one compressor runs while any unit on it calls. A wider gap in mild
# weather, its units on and off together; and a least time running and
# stopped. Each off until set; the radiators leading in mild weather are
# PumpBackupTest's.
class ShortCyclingTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    MILD = 12.0
    STOPPED = { "pump" => PumpState.new(running: false, switched_ago: 3) }
              .freeze

    def test_nothing_changes_until_set
        assert_equal({ "unit:a" => [:power, false, true] },
                     power(plan([room("a", 19.5)])))
    end

    # Mild, the pump stopped: no room a degree under, nothing starts.
    def test_a_stopped_pump_waits_for_a_room_a_degree_under
        result = plan([room("a", 19.5), room("b", 19.5)], pump(wait_above: 8.0))
        assert_empty power(result)
    end

    # One room a degree under: every unit whose room is under its target
    # starts with it, one run for both; a room already warm stays off.
    def test_a_started_pump_takes_every_room_under_its_target
        rooms = [room("a", 18.9), room("b", 19.5), room("c", 20.2)]
        assert_equal({ "unit:a" => [:power, false, true],
                       "unit:b" => [:power, false, true] },
                     power(plan(rooms, pump(wait_above: 8.0))))
    end

    # Running: a room reaching its target lets its unit go, and the last
    # one stops the pump.
    def test_a_running_pump_stops_when_no_room_is_under
        settings = pump(wait_above: 8.0)
        rooms = [room("a", 19.5, on: true), room("b", 20.1, on: true)]
        result = plan(rooms, settings)
        assert_equal({ "unit:b" => [:power, true, false] }, power(result))
        assert_equal ["quick, pump wait, +20.0..+26.0, at 20.1"],
                     result.actions.map(&:why)
        warm = [room("a", 20.0, on: true), room("b", 20.1, on: true)]
        assert_equal({ "unit:a" => [:power, true, false],
                       "unit:b" => [:power, true, false] },
                     power(plan(warm, settings)))
    end

    # quiet rests the loud unit; the pump started 5 min ago runs its 15.
    def test_a_pump_runs_its_least_time
        least = pump(min_on: 15)
        early = plan([quiet], least, state(running: true, ago: 5))
        assert_empty power(early)
        assert_includes early.warnings,
                        "pump: kept running: started 5 min ago, at least 15"
        assert_equal({ "unit:a" => [:power, true, false] },
                     power(plan([quiet], least, state(running: true,
                                                      ago: 20))))
    end

    def test_an_exclusion_or_a_room_too_warm_ends_the_least_time
        least = pump(min_on: 15)
        running = state(running: true, ago: 5)
        red = room("a", 19.5, on: true).with(excluded: %w[electricity])
        assert_equal({ "unit:a" => [:power, true, false] },
                     power(plan([red], least, running)))
        hot = quiet.with(measured: 21.5)
        cooled = plan([hot], least, running)
        assert_equal({ "unit:a" => [:power, true, false] }, power(cooled))
        assert_equal "quiet, urgent, run ended, +20.0..+26.0, at 21.5",
                     cooled.actions.first.why
    end

    def test_a_pump_stays_stopped_its_least_time_unless_a_room_is_cold
        early = plan([room("a", 19.5)], pump(min_off: 10), STOPPED)
        assert_empty power(early)
        assert_includes early.warnings,
                        "pump: kept stopped: stopped 3 min ago, at least 10"
        assert_equal({ "unit:a" => [:power, false, true] },
                     power(plan([room("a", 18.5)], pump(min_off: 10),
                                STOPPED)))
    end

    # A room urgent ends the rest for every unit, each saying so.
    def test_an_urgent_room_s_rest_ended_is_said
        cold = plan([room("a", 18.5), room("b", 19.5)], pump(min_off: 10),
                    STOPPED)
        assert_equal({ "unit:a" => [:power, false, true],
                       "unit:b" => [:power, false, true] }, power(cold))
        assert_equal "quick, rest ended: a urgent, +20.0..+26.0, at 19.5",
                     cold.actions.last.why
    end

    # Unknown since when, no least time.
    def test_an_unknown_switch_time_holds_nothing
        assert_equal({ "unit:a" => [:power, false, true] },
                     power(plan([room("a", 19.5)], pump(min_off: 10),
                                state(running: false, ago: nil))))
    end

    def test_a_negative_setting_is_refused
        assert_raises(ArgumentError) { PumpSettings.new(min_on: -1) }
        assert_raises(ArgumentError) { PumpSettings.new(wait: -1) }
    end

    private

    def pump(**) = StrategySettings.new(pump: PumpSettings.new(**))

    def state(running:, ago:)
        { "pump" => PumpState.new(running:, switched_ago: ago) }
    end

    def plan(rooms, settings = StrategySettings.new, pumps = {})
        Plan.new(rooms, settings:, pumps:).run
    end

    # { unit label => [:power, from, to] }
    def power(result)
        result.actions.select { it.setting == :power }
              .to_h { [it.device, [it.setting, it.from, it.to]] }
    end

    # quiet, a quiet radiator beside the loud unit, on, at 19.5.
    def quiet
        room("a", 19.5, on: true).then do |each|
            each.with(strategy: :quiet, radiators: [radiator("a")])
        end
    end

    # Zone name at temperature, mild outside, its unit on the one pump,
    # off unless said, the first unit its system's master.
    def room(name, temperature, on: false)
        unit = Aircon.new(ref: name, label: "unit:#{name}", caps: AIRCON_CAPS,
                          system: "h:1", source: "pump", master: name == "a",
                          temperature: nil, on:, mode: :heat,
                          setpoint: 20.0, range: 15.0..30.0, step: 0.5)
        Room.new(zone: name, band: BAND, strategy: :quick, aircons: [unit],
                 radiators: [], measured: temperature, outside: MILD)
    end

    def radiator(name)
        Radiator.new(ref: name, label: "valve:#{name}", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
