# frozen_string_literal: true

module Thermidor
    module Planner
        # The actions that bring each room's devices to what its band and
        # strategy ask, given the direction of each heat pump. With a
        # translation (AsIs says what one answers), a device's target is
        # the band's made into what its own sensor reads when the room
        # holds it.
        class Plan
            include DevicePlan
            include HeldDevices

            # Modes a system runs in without its heat pump.
            ASIDE = %i[fan dry].freeze

            # Modes a unit keeps when the heat pump has no direction.
            RUNNING = %i[fan dry auto].freeze

            # A direction's verb, for a warning's sentence.
            DOING = { heat: "heating", cool: "cooling" }.freeze

            # The direction a system's mode heats or cools in: aux is
            # heat with a backup heater; nil for the rest.
            def self.direction_of(mode)
                return :heat if mode == :aux
                mode if %i[heat cool].include?(mode)
            end

            # held: { source => :heat, :cool or nil }, heat pumps'
            # directions set outside the planner and held; aside: the
            # systems (their labels) left to themselves, whose mode is not
            # set.
            def initialize(rooms, settings: StrategySettings.new,
                           translation: AsIs.new, held: {}, aside: [])
                @rooms       = rooms
                @settings    = settings
                @translation = translation
                @held        = held
                @aside       = aside
            end

            def run
                @actions  = Actions.new
                @warnings = []
                sources.each { |source, rooms| pump(source, rooms) }
                @rooms.each do |room|
                    radiators(room)
                    unheated(room)
                    against_band(room)
                end
                Result.new(actions: @actions.to_a,
                           warnings: @warnings + @translation.notes)
            end

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
                source.unserved.each do |room|
                    @warnings << "#{room.zone}: needs #{room.need}, but " \
                                 "#{source} #{source.direction || "stays off"}"
                end
                held_against(source)
            end

            # A unit held by hand on a source whose other rooms just gave
            # it the other direction: its own room did not vote, so it
            # would otherwise lose its hand silently.
            def held_against(source)
                source.overridden.each do |room, unit|
                    was = DOING.fetch(Plan.direction_of(unit.mode))
                    now = DOING.fetch(source.direction)
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
                target = aircon_target(room, direction)
                room.aircons.select { it.source == source.name }
                    .reject { direction.nil? && RUNNING.include?(it.mode) }
                    .each { aircon(room, it, target, direction) }
            end

            # The setpoint a room's air conditioning should hold in
            # `direction`, nil for off.
            def aircon_target(room, direction)
                return if direction.nil? || room.need == opposite(direction)
                return room.band&.cool if direction == :cool
                Strategy.heat(room, @settings)[:aircon]
            end

            # A room needing heat whose devices may not heat now.
            def unheated(room)
                return if room.excluded.empty? || room.need != :heat
                return if Strategy.heat(room, @settings).values.any?
                @warnings << "#{room.zone}: needs heat, but " \
                             "#{room.excluded.join(", ")} is excluded now"
            end

            def opposite(direction) = direction == :heat ? :cool : :heat

            def change(...) = @actions.change(...)

            def retarget(...) = @actions.retarget(...)
        end
    end
end
