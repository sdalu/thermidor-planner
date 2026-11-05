# frozen_string_literal: true

module Thermidor
    module Planner
        # What Plan does against a heat pump's short cycles (PumpSettings,
        # the settings' pump): a unit's wider gap in mild weather, and its
        # least time on and off.
        module CyclePlan
            private

            # target, or nil while mild weather keeps the unit off: off,
            # until the room is mild_deadband under it; on, once the room
            # reaches it.
            def gapped(room, device, target, direction)
                pump = @settings.pump
                return target unless target && direction == :heat &&
                                     pump.mild?(room.outside)
                now = room.temperature or return target
                limit = device.on ? target : target - pump.mild_deadband
                target if now < limit
            end

            # Whether the unit stays as it is (state: :on or :off) for its
            # least time, said when it does.
            def kept?(room, device, direction, state)
                least = @settings.pump.public_send(:"min_#{state}") or
                    return false
                ago = device.switched_ago or return false
                return false if ago >= least ||
                                freed?(room, device, direction, state)
                @warnings << "#{room.zone}: #{device.label} kept #{state}: " \
                             "switched #{ago.round} min ago, at least #{least}"
                true
            end

            # What ends a least time: on, its energy excluded now, a
            # direction it does not run, or the room urgent past its band
            # the warm way; off, the room urgent past it the cold way.
            def freed?(room, device, direction, state)
                return urgent?(room, direction, :cold) if state == :off
                !Roles.heats?(device, room.excluded) ||
                    Plan.direction_of(device.mode) != direction ||
                    urgent?(room, direction, :warm)
            end

            # Whether the room is urgent °C past its band, the cold or
            # the warm way, for the direction run.
            def urgent?(room, direction, way)
                now = room.temperature or return false
                band = room.band or return false
                urgent = @settings.pump.urgent
                warm = (way == :warm) == (direction != :cool)
                side = direction == :cool ? band.cool : band.heat
                return false unless side
                warm ? now > side + urgent : now < side - urgent
            end
        end
    end
end
