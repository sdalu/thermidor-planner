# frozen_string_literal: true

require "test_helper"

# A pump's weather is mild only when every room on it that gives an
# outside temperature gives a mild one, whichever is listed first.
class WaitWeatherTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # Stopped, both rooms half a degree under: mild holds the pump off
    # until one is a degree under; not mild, both start.
    def test_one_room_not_mild_is_not_mild_weather
        [[12.0, 5.0], [5.0, 12.0]].each do |outsides|
            assert_equal [true, true], powers(outsides), outsides.inspect
        end
    end

    def test_every_room_mild_is_mild_weather
        assert_empty plan([12.0, 10.0]).actions
    end

    # A room giving no outside temperature has no say.
    def test_a_room_with_no_outside_has_no_say
        assert_empty plan([nil, 12.0]).actions
    end

    # A room whose units are all unread still gives the outside: the
    # weather is mild by it, the other room giving none.
    def test_a_room_with_no_unit_planned_still_says_the_weather
        unread = Room.new(zone: "u", band: BAND, strategy: :quick,
                          radiators: [], measured: 19.5, outside: 12.0,
                          aircons: [unit(1).with(mode: nil, on: nil)])
        read = Room.new(zone: "r", band: BAND, strategy: :quick,
                        radiators: [], aircons: [unit(0)], measured: 19.5)
        settings = StrategySettings.new(pump: PumpSettings.new(wait_above: 8.0))
        pumps = { "pump" => PumpState.new(running: false) }
        result = Plan.new([unread, read], settings:, pumps:).run
        assert(result.actions.none? { it.setting == :power })
    end

    private

    def powers(outsides)
        plan(outsides).actions.select { it.setting == :power }.map(&:to)
    end

    def plan(outsides)
        rooms = outsides.each_with_index.map do |outside, i|
            Room.new(zone: "r#{i}", band: BAND, strategy: :quick,
                     radiators: [], aircons: [unit(i)], measured: 19.5,
                     outside:)
        end
        settings = StrategySettings.new(pump: PumpSettings.new(wait_above: 8.0))
        pumps = { "pump" => PumpState.new(running: false) }
        Plan.new(rooms, settings:, pumps:).run
    end

    def unit(id)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: id.zero?,
                   temperature: nil, on: false, mode: :heat,
                   setpoint: 20.0, range: 15.0..30.0, step: 0.5)
    end
end
