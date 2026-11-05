# frozen_string_literal: true

module Thermidor
    module Planner
        # Plan's heat pumps: each one's direction from the rooms it serves
        # (Source), its systems' modes set through their masters, its units
        # planned in that direction, and the rooms it leaves needing heat
        # cut from it for their radiators.
        module PumpPlan
            private

            # { Source => [Room, ...] } over the rooms with air conditioning,
            # held or not.
            def sources
                pairs = @rooms.flat_map do |room|
                    units(room).map { [it.source, room] }
                end
                pairs.group_by(&:first).to_h do |name, found|
                    rooms = found.map(&:last).uniq
                    [source(name, rooms), rooms]
                end
            end

            # Its direction from the rooms with a unit of its own in the
            # plan: one switched off by hand cannot use it, nor one of a
            # system set aside, held from the start (Plan#holding_aside).
            def source(name, rooms)
                Source.new(name, rooms, current(rooms, name), @settings,
                           state: @pumps[name] || PumpState.new)
            end

            # The room's units, held or not; on source only when given.
            def units(room, source = nil)
                all = room.aircons + room.held.grep(Aircon)
                source ? all.select { it.source == source } : all
            end

            def current(rooms, source)
                masters(rooms, source).map { Plan.direction_of(it.mode) }
                                      .compact.first
            end

            # A unit standing for each system, its master's when there: the
            # mode is the system's, every unit reports it, and it is set
            # through the master whichever stands. One unread (nil mode)
            # never stands: its system's mode would read as unknown.
            def masters(rooms, source)
                rooms.flat_map { units(it, source) }.select(&:mode)
                     .sort_by { it.master ? 0 : 1 }
                     .uniq(&:system)
                     .reject { @aside.include?(it.system) }
            end

            def pump(source, rooms)
                masters(rooms, source.name).each { mode(source, it) }
                units_of(source, rooms)
                unserved(source)
                held_against(source)
            end

            # Its units, planned as one, and the zones it leaves to their
            # radiators.
            def units_of(source, rooms)
                cycle = cycle(source, rooms)
                targets = cycle.targets
                rooms.each { aircons(it, source, targets) }
                @warnings.concat(cycle.warnings)
                cut(source, cycle.rested + source.stepped.map(&:zone))
            end

            # Its units planned as one (PumpCycle), from each one's target.
            def cycle(source, rooms)
                entries = rooms.flat_map do |room|
                    targets = aircon_targets(room, source.direction)
                    planned(room, source).select(&:mode).map do |unit|
                        [room, unit, targets[unit.label]]
                    end
                end
                PumpCycle.new(source, entries, @settings.pump,
                              @pumps[source.name],
                              outsides: rooms.filter_map(&:outside))
            end

            # The room's units on source that are planned: with no
            # direction, one in fan, dry or auto is left running.
            def planned(room, source)
                direction = source.direction
                room.aircons.select { it.source == source.name }
                    .reject { direction.nil? && Plan::RUNNING.include?(it.mode) }
            end

            # The zones the pump leaves to their radiators (#uncut): those
            # stepping aside, those whose units it holds while it rests.
            def cut(source, zones)
                zones.each { @cut[it] << source.name }
            end

            # A system's mode, set through its master zone; one in aux is
            # heating already. Left in auto with no direction to give, said.
            def mode(source, master)
                wanted = source.direction
                return left_in_auto(source, master) if wanted.nil?
                return if Plan.direction_of(master.mode) == wanted
                @actions.mode(master.system, master.mode, wanted, source)
            end

            # Each planned unit of the room on source to its target.
            def aircons(room, source, targets)
                planned(room, source).each do |unit|
                    target = targets[[room.zone, unit.label]]
                    aircon(room, unit, target, source.direction)
                end
            end

            # { label => the setpoint each unit should hold in `direction`,
            # nil for off }: a unit that cannot cool has none to cool.
            def aircon_targets(room, direction)
                return {} if direction.nil? || room.need == opposite(direction)
                return Strategy.heat(room, @settings) if direction == :heat
                room.aircons.to_h do |unit|
                    [unit.label, (room.band&.cool if Roles.cools?(unit))]
                end
            end
        end
    end
end
