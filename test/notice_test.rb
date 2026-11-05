# frozen_string_literal: true

require "test_helper"

# Every warning is a Notice: today's sentence as text, its kind and
# what it is about; a translation's notes come after, as given.
class NoticeTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # A translation noting what it could not translate.
    class Noting < AsIs
        def notes = ["sensor: no offset"]
    end

    # valve:1 unread, valve:2 with no range nor least, gas excluded.
    def test_a_radiator_unread_with_no_least_and_unheated
        cold = room(18.0, radiators: [valve(1, mode: nil),
                                      valve(2, range: nil)])
        assert_notices plan(cold.with(excluded: %w[gas])),
                       [["office: valve:1 not read: left as it is",
                         :unread, "office", "valve:1", nil],
                        ["office: valve:2 has no least target: left as " \
                         "it is", :no_least, "office", "valve:2", nil],
                        ["office: needs heat, but gas is excluded now",
                         :unheated, "office", nil, nil]]
    end

    def test_a_pump_s_room_unserved_and_a_unit_held_against_it
        held = unit(2, "h:2").with(mode: :heat)
        guest = room(28.0, zone: "guest", held: [held])
        cold = room(18.0, aircons: [unit(1, "h:1")])
        pumps = { "pump" => PumpState.new(held: :cool) }
        assert_notices plan(cold, guest, pumps:),
                       [["office: needs heat, but pump cool",
                         :unserved, "office", nil, "pump"],
                        ["guest: unit:2 held heating, the heat pump goes " \
                         "cooling", :held_against, "guest", "unit:2",
                         "pump"]]
    end

    def test_a_system_left_in_auto
        auto = unit(1, "h:1").with(mode: :auto)
        assert_notices plan(room(22.0, aircons: [auto])),
                       [["h:1: left in auto: the heat pump pump has no " \
                         "direction now", :left_in_auto, nil, "h:1",
                         "pump"]]
    end

    def test_a_held_valve_past_the_band
        hot = valve(1).with(mode: :heat, target: 28.0)
        assert_notices plan(room(22.0, held: [hot])),
                       [["office: valve:1 left on, heating to 28.0 °C, " \
                         "above the band's cool side 26.0 °C",
                         :past_band, "office", "valve:1", nil]]
    end

    # No band: its unit would go off, but the pump runs its least.
    def test_a_pump_kept_running
        settings = StrategySettings.new(pump: PumpSettings.new(min_on: 15))
        pumps = { "pump" => PumpState.new(running: true, switched_ago: 5) }
        warm = room(23.0, aircons: [unit(1, "h:1")]).with(band: nil)
        assert_notices plan(warm, settings:, pumps:),
                       [["pump: kept running: started 5 min ago, at " \
                         "least 15", :kept, nil, nil, "pump"]]
    end

    def test_a_translation_s_notes_stay_as_given
        warnings = Plan.new([room(22.0)], translation: Noting.new).run.warnings
        assert_equal ["sensor: no offset"], warnings
        refute_kind_of Notice, warnings.first
    end

    private

    def assert_notices(result, expected)
        assert_equal expected.map(&:first), result.warnings
        result.warnings.zip(expected).each do |notice, (_, *about)|
            assert_kind_of Notice, notice
            assert_equal about, [notice.kind, notice.zone, notice.device,
                                 notice.source]
        end
    end

    def plan(*rooms, **) = Plan.new(rooms, **).run

    def room(temperature, zone: "office", radiators: [], aircons: [],
             held: [])
        Room.new(zone:, band: BAND, strategy: :quick, radiators:, aircons:,
                 held:, measured: temperature)
    end

    def valve(id, mode: :heat, range: 5.0..25.0)
        Radiator.new(ref: id.to_s, label: "valve:#{id}", caps: RADIATOR_CAPS,
                     temperature: nil, mode:, target: 20.0, range:,
                     step: 0.5)
    end

    def unit(id, system)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps: AIRCON_CAPS,
                   system:, source: "pump", master: true, temperature: nil,
                   on: true, mode: :heat, setpoint: 20.0, range: 15.0..30.0,
                   step: 0.5)
    end
end
