# frozen_string_literal: true

require "test_helper"

# A unit of a system set aside is held from the start of the plan: not
# planned, ranked or voted through, its reading still the room's; so a
# room it leaves cold is its radiators' and said, whatever else is
# beside it.
class AsideHeldTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)

    # Beside an unread unit on the same pump, the radiator still heats.
    def test_a_unit_set_aside_and_one_unread_leave_it_to_the_radiator
        office = room("office", 18.0, valve: true,
                                      aircons: [unit(1, "h:2", on: false),
                                                unit(3, "h:1", mode: nil)])
        assert_includes targets(plan([office], aside: %w[h:2])),
                        ["valve:1", 20.0]
    end

    # Beside a radiator whose energy is excluded now, the room is said;
    # left only to units held, it is the caller's (a zone handed over).
    def test_a_room_its_set_aside_unit_leaves_cold_is_said
        office = room("office", 18.0, valve: true,
                                      aircons: [unit(1, "h:2", on: false)])
                 .with(excluded: %w[gas])
        assert_includes plan([office], aside: %w[h:2]).warnings,
                        "office: needs heat, but gas is excluded now"
        alone = office.with(radiators: [], excluded: [])
        assert_empty plan([alone], aside: %w[h:2]).warnings
    end

    # office reads 23 on its set-aside unit, 17 on the other: 20.0, no
    # need, so it does not turn the pump against the hot guest room.
    def test_a_unit_set_aside_still_reads_its_room
        office = room("office", nil,
                      aircons: [unit(1, "h:2", temperature: 23.0),
                                unit(3, "h:1", temperature: 17.0,
                                               mode: :cool)])
        guest = room("guest", 27.0,
                     aircons: [unit(2, "h:1", mode: :cool, master: false)])
        result = plan([office, guest], aside: %w[h:2])
        refute(result.actions.any? { it.setting == :mode })
        assert_includes targets(result), ["unit:2", 26.0]
    end

    # A unit switched off by hand still reads its room.
    def test_a_held_device_s_reading_counts
        held = unit(1, "h:1", temperature: 22.0)
        room = room("office", nil, aircons: [unit(2, "h:1", temperature: 18.0)])
               .with(held: [held])
        assert_in_delta 20.0, room.temperature
    end

    private

    def plan(rooms, aside: []) = Plan.new(rooms, aside:).run

    def targets(result)
        result.actions.map { [it.device, it.to] }
    end

    def room(zone, temperature, aircons:, valve: false)
        Room.new(zone:, band: BAND, strategy: :cheapest, aircons:,
                 radiators: valve ? [radiator] : [], measured: temperature)
    end

    def radiator
        Radiator.new(ref: "1", label: "valve:1", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 5.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end

    # Unit id of system on the one pump, on in heat at 20 unless said.
    def unit(id, system, **fields)
        Aircon.new(ref: id.to_s, label: "unit:#{id}", caps: AIRCON_CAPS,
                   system:, source: "pump", master: true, temperature: nil,
                   on: true, mode: :heat, setpoint: 20.0, range: 15.0..30.0,
                   step: 0.5, **fields)
    end
end
