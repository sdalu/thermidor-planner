# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A plan works out each room's strategy (Roles) once (StrategyCache),
# though it asks for it again for the heat pump's vote, the radiators
# and each action's why.
class PlanStrategyOnceTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 24)

    def test_each_room_s_roles_are_built_once
        rooms = [room("office", 0, :comfort), room("guest", 1, :quick)]
        result, built = built_zones { Plan.new(rooms).run }
        rooms.each do |room|
            assert_operator changes(result, room), :>=, 2,
                            "#{room.zone}: asked more than once"
        end
        assert_equal({ "office" => 1, "guest" => 1 }, built.tally)
    end

    private

    # What the block gives, and the zones of the rooms Roles was built
    # for meanwhile.
    def built_zones(&)
        built = []
        build = Roles.method(:new)
        found = Roles.stub(:new, lambda { |room, *rest|
            built << room.zone
            build.call(room, *rest)
        }, &)
        [found, built]
    end

    def changes(result, room) = result.actions.count { it.zone == room.zone }

    # A cold room: two gas radiators, and a unit off on the one heat
    # pump (master when id is 0), each to be changed.
    def room(zone, id, strategy)
        radiators = Array.new(2) { radiator("#{zone}#{it}") }
        Room.new(zone:, band: BAND, strategy:, radiators:,
                 aircons: [unit(id)], measured: 17.0)
    end

    def radiator(name)
        Radiator.new(ref: name, label: "valve:#{name}", caps: RADIATOR_CAPS,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5)
    end

    def unit(id)
        Aircon.new(ref: "h:1:#{id}", label: "unit:#{id}", caps: AIRCON_CAPS,
                   system: "h:1", source: "pump", master: id.zero?,
                   temperature: nil, on: false, mode: :heat, setpoint: 19.0,
                   range: 15.0..30.0, step: 0.5)
    end
end
