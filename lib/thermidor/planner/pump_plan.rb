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
            # plan: one switched off by hand cannot use it.
            def source(name, rooms)
                held = @held.fetch(name, :none)
                Source.new(name, rooms, current(rooms, name), @settings,
                           held: held == :none ? Source::FREE : held)
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
                rooms.each { aircons(it, source) }
                unserved(source)
                held_against(source)
            end

            # The rooms needing what the pump does not give, said; one
            # needing heat is cut from it, for its radiators (#uncut).
            def unserved(source)
                source.unserved.each do |room|
                    @cut[room.zone] << source.name if room.need == :heat
                    @warnings << "#{room.zone}: needs #{room.need}, but " \
                                 "#{source} #{source.direction || "stays off"}"
                end
            end

            # A unit held by hand on a source whose other rooms just gave
            # it the other direction: its own room did not vote, so it
            # would otherwise lose its hand silently.
            def held_against(source)
                source.overridden.each do |room, unit|
                    was = Plan::DOING.fetch(Plan.direction_of(unit.mode))
                    now = Plan::DOING.fetch(source.direction)
                    @warnings << "#{room.zone}: #{unit.label} " \
                                 "held #{was}, the heat pump goes #{now}"
                end
            end

            # A system's mode, set through its master zone; one in aux is
            # heating already. Left in auto with no direction to give, said.
            def mode(source, master)
                wanted = source.direction
                return left_in_auto(source, master) if wanted.nil?
                return if Plan.direction_of(master.mode) == wanted
                @actions.mode(master.system, master.mode, wanted, source)
            end

            def left_in_auto(source, master)
                return unless master.mode == :auto
                @warnings << "#{master.system}: left in auto: the heat " \
                             "pump #{source} has no direction now"
            end

            # With no direction, a unit in fan, dry or auto is left running.
            def aircons(room, source)
                direction = source.direction
                targets = aircon_targets(room, direction)
                room.aircons.select { it.source == source.name }
                    .reject { direction.nil? && Plan::RUNNING.include?(it.mode) }
                    .each { aircon(room, it, targets[it.label], direction) }
            end

            # { label => the setpoint each unit should hold in `direction`,
            # nil for off }.
            def aircon_targets(room, direction)
                return {} if direction.nil? || room.need == opposite(direction)
                return Strategy.heat(room, @settings) if direction == :heat
                room.aircons.to_h { [it.label, room.band&.cool] }
            end

            # The room as its radiators are planned: without the units of
            # a heat pump that leaves it needing heat, so the radiators
            # heat it as they would a room with no unit.
            def uncut(room)
                cut = @cut[room.zone]
                return room if cut.empty?
                room.with(aircons: room.aircons.reject do |unit|
                    cut.include?(unit.source)
                end)
            end
        end
    end
end
