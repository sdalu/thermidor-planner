# frozen_string_literal: true

require "test_helper"

# The radiators leading in mild weather (PumpSettings backup_above), per
# room: a room needing little heat heats with its radiators, its units a
# comfort gap behind, whatever the strategy.
class PumpBackupTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    LEAD = StrategySettings.new(pump: PumpSettings.new(backup_above: 8.0))
    UNIT_LEADS = { "valve:a" => nil, "unit:a" => 20.0 }.freeze

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

    # Under 8.0 °C outside, the lead holds down to 7.5 for a room whose
    # radiators alone led last (Room#led); not for one whose unit led,
    # nor one both led (quick, say).
    def test_radiators_leading_keep_the_lead_within_the_deadband
        assert_equal({ "valve:a" => 20.0, "unit:a" => 19.5 },
                     lead_at(7.7, %w[valve:a]))
        assert_equal UNIT_LEADS, lead_at(7.4, %w[valve:a])
    end

    def test_under_backup_above_no_other_lead_is_kept
        [nil, %w[unit:a], %w[valve:a unit:a]].each do |led|
            assert_equal UNIT_LEADS, lead_at(7.7, led), led.inspect
        end
    end

    def test_a_deadband_of_none_swaps_at_backup_above
        sharp = StrategySettings.new(
            pump: PumpSettings.new(backup_above: 8.0, backup_kept: 0.0)
        )
        assert_equal({ "valve:a" => nil, "unit:a" => 20.0 },
                     Strategy.heat(cheap.with(outside: 7.9,
                                              led: %w[valve:a]), sharp))
    end

    def test_a_nil_or_negative_deadband_is_refused
        assert_raises(ArgumentError) { PumpSettings.new(backup_kept: nil) }
        assert_raises(ArgumentError) { PumpSettings.new(backup_kept: -1) }
    end

    # Each write the lead made says so, and how far mild the weather is.
    def test_why_names_the_pump_backup
        assert_equal ["cheapest, pump backup (12.0 °C ≥ 8.0), +20.0..+26.0, " \
                      "at 19.5"] * 2,
                     whys(cheap)
        kept = cheap.with(outside: 7.7, led: %w[valve:a])
        assert_equal ["cheapest, pump backup kept (7.7 °C ≥ 7.5), " \
                      "+20.0..+26.0, at 19.5"] * 2,
                     whys(kept)
    end

    # comfort leads with the radiator anyway: the lead changes nothing,
    # and is not said.
    def test_a_lead_changing_nothing_is_not_said
        comfort = cheap.with(strategy: :comfort)
        assert_equal ["comfort, +20.0..+26.0, at 19.5"] * 2, whys(comfort)
    end

    private

    def lead_at(outside, led)
        Strategy.heat(cheap.with(outside:, led:), LEAD)
    end

    def whys(room) = Plan.new([room], settings: LEAD).run.actions.map(&:why)

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
