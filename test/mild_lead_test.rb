# frozen_string_literal: true

require "test_helper"

# The radiators leading in mild weather (PumpSettings mild_lead), per
# room: a room needing little heat heats with its radiators, its units a
# comfort gap behind, whatever the strategy.
class MildLeadTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    LEAD = StrategySettings.new(pump: PumpSettings.new(mild_lead: 8.0))

    # cheapest leads with the unit; mild and a room less than a degree
    # under its band, the radiator leads and the unit backs up.
    def test_radiators_lead_in_mild_weather
        assert_equal({ "valve:a" => nil, "unit:a" => 20.0 },
                     Strategy.heat(cheap, StrategySettings.new))
        assert_equal({ "valve:a" => 20.0, "unit:a" => 19.5 },
                     Strategy.heat(cheap, LEAD))
    end

    def test_a_cold_room_or_cold_weather_keeps_the_strategy
        unit_leads = { "valve:a" => nil, "unit:a" => 20.0 }
        assert_equal unit_leads,
                     Strategy.heat(cheap.with(measured: 18.5), LEAD)
        assert_equal unit_leads,
                     Strategy.heat(cheap.with(outside: 5.0), LEAD)
    end

    private

    # cheapest with a radiator beside the unit, mild, at 19.5.
    def cheap
        Room.new(zone: "a", band: BAND, strategy: :cheapest,
                 aircons: [unit], radiators: [valve], measured: 19.5,
                 outside: 12.0)
    end

    def unit
        Aircon.new(ref: "a", label: "unit:a", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: true,
                   temperature: nil, on: true, mode: :heat, setpoint: 20.0,
                   range: 15.0..30.0, step: 0.5)
    end

    def valve
        Radiator.new(ref: "a", label: "valve:a", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end
end
