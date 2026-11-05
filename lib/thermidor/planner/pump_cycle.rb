# frozen_string_literal: true

module Thermidor
    module Planner
        # What the caller knows of a heat pump: held, a direction set
        # outside the planner and held (:heat, :cool, nil for neither;
        # Source::FREE for none); running, whether its compressor runs now
        # (nil: unknown, taken as whether one of its units is on);
        # switched_ago, minutes since it last started or stopped (nil:
        # unknown).
        PumpState = Data.define(:held, :running, :switched_ago) do
            def initialize(held: Source::FREE, running: nil,
                           switched_ago: nil)
                super
            end
        end

        # A heat pump's units planned as one, against short cycles (the
        # settings' pump, PumpSettings): one compressor runs while any of
        # its units calls, so its starts are what wear, not a unit's.
        # Given each unit's target, it gives each a target, nil for off,
        # or KEEP for as it is.
        class PumpCycle
            # A unit left as it is: power and setpoint unwritten.
            KEEP = Object.new.freeze

            # entries: [[room, unit, target or nil], ...], the pump's units
            # planned; state: its PumpState, nil unknown.
            def initialize(source, entries, settings, state)
                @source    = source
                @entries   = entries
                @settings  = settings
                @state     = state || PumpState.new
                @warnings  = []
            end

            # warnings: what it said; rested: the zones needing heat whose
            # units it holds while the pump rests, for their radiators.
            attr_reader :warnings

            def rested = @rested || []

            # { [zone, unit label] => target, nil or KEEP }.
            def targets
                found = mild? ? gapped : @entries
                held(found).to_h do |room, unit, target|
                    [[room.zone, unit.label], target]
                end
            end

            private

            def direction = @source.direction

            def running?
                return @state.running unless @state.running.nil?
                @entries.any? { |_, unit, _| unit.on }
            end

            # Mild weather, heating, every room's temperature known.
            def mild?
                return false unless direction == :heat
                outside = @entries.filter_map { |room, _, _| room.outside }
                                  .first
                @settings.mild?(outside) &&
                    @entries.all? { |room, _, _| room.temperature }
            end

            # Running, until no room is under its unit's target, then every
            # unit off together; stopped, until a room is mild_deadband
            # under it, then every unit whose room is under its target on
            # together. A unit whose room is not under its target is off,
            # the others carrying the run.
            def gapped
                margin = running? ? 0.0 : @settings.mild_deadband
                calls = @entries.any? do |room, _, target|
                    under?(room, target, margin)
                end
                @entries.map do |room, unit, target|
                    [room, unit, (target if calls && under?(room, target, 0.0))]
                end
            end

            def under?(room, target, margin)
                target && room.temperature < target - margin
            end

            # Its least time running or stopped, said when it holds a
            # unit's power: running, its units on are left as they are;
            # stopped, none is switched on or given a new setpoint, until
            # a room urgent past its band starts it, which ends the rest.
            def held(entries)
                ago = @state.switched_ago or return entries
                least = running? ? @settings.min_on : @settings.min_off
                return entries unless least && ago < least
                if running?
                    run(entries, ago, least)
                else
                    rest(entries, ago, least)
                end
            end

            def run(entries, ago, least)
                said = entries.any? do |room, unit, target|
                    target.nil? && kept_on?(room, unit)
                end
                say(ago, least) if said
                entries.map { |entry| kept_on?(*entry) ? kept(entry) : entry }
            end

            def rest(entries, ago, least)
                return entries if entries.any? { starts?(*it) }
                held = entries.select(&:last)
                @rested = zones_needing_heat(held)
                say(ago, least) if held.any? { |_, unit, _| !unit.on }
                entries.map { |entry| entry.last ? kept(entry) : entry }
            end

            # A unit on, kept so while the pump runs its least.
            def kept_on?(room, unit, _target = nil)
                unit.on && !freed?(room, unit)
            end

            # A unit off whose room is urgent past its band the cold way:
            # it starts the pump whatever its rest.
            def starts?(room, unit, target)
                target && !unit.on && urgent?(room, :cold)
            end

            def zones_needing_heat(entries)
                entries.map(&:first).select { it.need == :heat }
                       .map(&:zone).uniq
            end

            def kept(entry) = [*entry.first(2), KEEP]

            # What ends the least time running for a unit: its energy
            # excluded now, a direction it does not run, or its room
            # urgent past its band the warm way.
            def freed?(room, unit)
                (direction == :heat && !Roles.heats?(unit, room.excluded)) ||
                    Plan.direction_of(unit.mode) != direction ||
                    urgent?(room, :warm)
            end

            # Whether the room is urgent °C past its band the cold or the
            # warm way, for the direction run.
            def urgent?(room, way)
                now = room.temperature or return false
                side = direction == :cool ? room.band&.cool : room.band&.heat
                return false unless side
                margin = @settings.urgent
                warm = (way == :warm) == (direction != :cool)
                warm ? now > side + margin : now < side - margin
            end

            def say(ago, least)
                did = running? ? "running: started" : "stopped: stopped"
                @warnings << "#{@source}: kept #{did} #{ago.round} min " \
                             "ago, at least #{least}"
            end
        end
    end
end
