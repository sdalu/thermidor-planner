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
            include PumpPlan
            include HeldDevices

            # Modes a system runs in without its heat pump: what a caller
            # may set aside (aside:) when a system was put in one by hand.
            # The plan itself sets a system to its pump's direction
            # whatever its mode.
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

            # pumps: { source => PumpState }, what the caller knows of the
            # heat pumps (a direction held, running, since when); aside:
            # the systems (their labels) left to themselves, whose mode is
            # not set.
            def initialize(rooms, settings: StrategySettings.new,
                           translation: AsIs.new, pumps: {}, aside: [])
                @rooms       = rooms
                @settings    = settings
                @translation = translation
                @pumps       = pumps
                @aside       = aside
            end

            def run
                start
                sources.each { |source, rooms| pump(source, rooms) }
                @rooms.each do |room|
                    radiators(uncut(room))
                    unheated(room)
                    against_band(room)
                end
                Result.new(actions: @actions.to_a,
                           warnings: @warnings + @translation.notes)
            end

            private

            # cut: { zone => the heat pumps leaving it needing heat }.
            def start
                @actions  = Actions.new
                @warnings = []
                @cut      = Hash.new { |hash, zone| hash[zone] = [] }
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

            # A room needing heat that none of its devices heat, said with
            # why. One whose devices are all unread or held is not: an
            # unread one is said as such, and one held is the caller's (a
            # zone handed to its devices' own drivers, say).
            def unheated(room)
                return unless room.need == :heat
                read = (room.radiators + room.aircons).select(&:mode)
                return if read.empty?
                return if Strategy.heat(room, @settings).values.any?
                why = unheated_why(room, read)
                @warnings << "#{room.zone}: needs heat, but #{why}"
            end

            def unheated_why(room, read)
                able = read.select { it.caps&.heat }
                return "no device can heat it" if able.empty?
                if able.none? { Roles.heats?(it, room.excluded) }
                    return "#{room.excluded.join(", ")} is excluded now"
                end
                format("no device heats as low as %.1f °C", room.band.heat)
            end

            def opposite(direction) = direction == :heat ? :cool : :heat

            def change(...) = @actions.change(...)

            def retarget(...) = @actions.retarget(...)
        end
    end
end
