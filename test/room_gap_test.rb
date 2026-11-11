# frozen_string_literal: true

require "test_helper"

# A room's own comfort gap (Room#gap): how far under the lead its other
# devices come in, over the house's (StrategySettings#comfort), under
# comfort, the effects' preferred lead and the pump backup alike.
class RoomGapTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    def test_comfort_puts_the_others_the_room_s_gap_behind
        targets = Strategy.heat(room(gap: 1.5))
        assert_equal({ "valve:a" => 20.0, "unit:a" => 18.5 }, targets)
    end

    def test_without_its_own_the_room_takes_the_house_s
        assert_equal({ "valve:a" => 20.0, "unit:a" => 19.5 },
                     Strategy.heat(room))
        house = StrategySettings.new(comfort: 1.0)
        assert_equal({ "valve:a" => 20.0, "unit:a" => 19.0 },
                     Strategy.heat(room, house))
    end

    # A preferred energy leads; the others back up the room's gap behind.
    def test_a_preferred_lead_backs_up_the_room_s_gap_behind
        solar = Effects.none.with(preferred: %w[electricity])
        targets = Strategy.heat(room(gap: 2.0).with(effects: solar))
        assert_equal({ "valve:a" => 18.0, "unit:a" => 20.0 }, targets)
    end

    # Radiators leading in mild weather, the units their backup the
    # room's gap behind.
    def test_the_pump_backup_takes_the_room_s_gap
        mild = StrategySettings.new(
            pump: PumpSettings.new(backup_above: 10.0)
        )
        backed = room(gap: 2.0, strategy: :quick)
                 .with(outside: 12.0, measured: 19.5)
        assert_equal({ "valve:a" => 20.0, "unit:a" => 18.0 },
                     Strategy.heat(backed, mild))
    end

    def test_a_negative_gap_is_refused
        assert_raises(ArgumentError) { room(gap: -0.5) }
    end

    private

    def room(gap: nil, strategy: :comfort)
        Room.new(zone: "a", band: BAND, strategy:, radiators: [valve],
                 aircons: [unit], measured: 19.0, gap:)
    end

    def valve
        Radiator.new(ref: "a", label: "valve:a", caps: RADIATOR_CAPS,
                     temperature: 19.0, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5)
    end

    def unit
        Aircon.new(ref: "a", label: "unit:a", caps: AIRCON_CAPS,
                   system: "system:a", source: "pump", master: true,
                   temperature: 19.0, on: false, mode: :heat,
                   setpoint: 22.0, range: 16.0..30.0, step: 0.5)
    end
end
