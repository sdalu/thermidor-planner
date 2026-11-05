# frozen_string_literal: true

module Thermidor
    module Planner
        # PumpCycle's least times (PumpSettings min_on, min_off): a pump
        # started (stopped) less than that ago has none of its units
        # switched off (on), unless a unit is freed or a room is urgent;
        # what is held is said, and what ends a hold noted for why.
        module LeastTimes
            private

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
                entries.map do |entry|
                    next kept(entry) if kept_on?(*entry)
                    ended(*entry)
                end
            end

            def rest(entries, ago, least)
                urgent = urgent_zones(entries)
                return started(entries, urgent) if urgent.any?
                held = entries.select(&:last)
                @rested = zones_needing_heat(held)
                say(ago, least) if held.any? { |_, unit, _| !unit.on }
                entries.map { |entry| entry.last ? kept(entry) : entry }
            end

            # A unit on, kept so while the pump runs its least.
            def kept_on?(room, unit, _target = nil)
                unit.on == true && !freed?(room, unit)
            end

            # A unit off whose room is urgent past its band the cold way:
            # it starts the pump whatever its rest.
            def starts?(room, unit, target)
                !target.nil? && !unit.on && urgent?(room, :cold)
            end

            # A unit on switched off within the least run, its room urgent
            # past its band the warm way, said.
            def ended(room, unit, target)
                note(room, unit, "urgent, run ended") if
                    unit.on && target.nil? && urgent?(room, :warm)
                [room, unit, target]
            end

            # The zones whose units start the pump whatever its rest.
            def urgent_zones(entries)
                entries.select { starts?(*it) }.map { it.first.zone }.uniq
            end

            # The rest ended by the urgent zones, said for every unit
            # planned to heat.
            def started(entries, urgent)
                said = "rest ended: #{urgent.join(", ")} urgent"
                entries.each do |room, unit, target|
                    note(room, unit, said) if target
                end
            end

            def zones_needing_heat(entries)
                entries.map(&:first).select { it.need == :heat }
                       .map(&:zone).uniq
            end

            def kept(entry) = [*entry.first(2), PumpCycle::KEEP]

            # What ends the least time running for a unit: its energy
            # excluded now, a cooling it cannot give, a direction it does
            # not run, or its room urgent past its band the warm way.
            def freed?(room, unit)
                (direction == :heat && !Roles.heats?(unit, room.excluded)) ||
                    (direction == :cool && !Roles.cools?(unit)) ||
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
                @warnings << Notice.new("#{@source}: kept #{did} " \
                                        "#{ago.round} min ago, at least " \
                                        "#{least}",
                                        kind: :kept, source: @source.name)
            end
        end
    end
end
