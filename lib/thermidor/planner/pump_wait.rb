# frozen_string_literal: true

module Thermidor
    module Planner
        # Plan's radiators while a heat pump waits (PumpCycle#waits),
        # mild: stopped, it starts only once a room is wait °C under its
        # unit's target, its restart point. A
        # radiator heating up to there would hold the room above it and
        # the pump would never start, so one its room's strategy steps
        # back behind the unit heats no higher than backup_under under
        # that point: a safety net, the pump starting first and running
        # one long cycle. One leading with the unit, or ahead of it, is
        # left. Off (nil backup_under), the strategy's target stands.
        module PumpWait
            private

            # targets ({ label => target or nil }, Strategy.heat) with
            # the room's radiators behind the waiting unit lowered under
            # its restart point, said.
            def waiting(room, targets)
                unit = @waits[room.zone]
                ceiling = wait_ceiling(unit) or return targets
                room.radiators.each_with_object(targets.dup) do |device, all|
                    target = all[device.label]
                    next unless target && target < unit && target > ceiling
                    all[device.label] = ceiling
                    held_under(room, device, ceiling)
                end
            end

            # The restart point less backup_under; nil when the room's
            # pump is not waiting or the margin is off.
            def wait_ceiling(unit)
                pump = @settings.pump
                return unless unit && pump.backup_under
                (unit - pump.wait - pump.backup_under).round(1)
            end

            def held_under(room, device, ceiling)
                said = format("backup %.1f while the pump waits", ceiling)
                @actions.noted([room.zone, device.label] => [said])
            end
        end
    end
end
