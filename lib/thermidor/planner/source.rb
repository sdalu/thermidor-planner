# frozen_string_literal: true

module Thermidor
    module Planner
        # The one direction (:heat, :cool, or nil to stay off) of a heat
        # pump shared by `rooms`, from what they need, a room needing heat
        # counting only when its unit may heat it: on a conflict, rooms
        # needing heat that have radiators to give it drop out; then the
        # most rooms win, heat on a tie. With no need either way, the
        # direction it has (`current`) stays. A direction set outside
        # the planner and held (held: :heat, :cool or nil for neither) wins;
        # the rooms it does not serve are said.
        class Source
            # Nothing held.
            FREE = Object.new.freeze

            # name: the heat pump's, as its units' source gives it.
            attr_reader :name, :direction, :unserved, :overridden

            def initialize(name, rooms, current,
                           settings = StrategySettings.new, held: FREE)
                @name = name
                @settings = settings
                heats, cools = votes(voters(rooms))
                @direction = if held.equal?(FREE)
                                 choose(heats, cools) || current
                             else
                                 held
                             end
                @unserved   = left_out(heats, cools)
                @overridden = held_against(rooms)
            end

            def to_s = @name.to_s

            private

            # The rooms with a unit of their own on this source: one held
            # off by hand does not vote, nor does one unread (nil mode):
            # it cannot be known to want either direction.
            def voters(rooms)
                rooms.select { |room| voting?(room) }
            end

            def voting?(room)
                room.aircons.any? { it.source == @name && it.mode }
            end

            def votes(rooms)
                heats = rooms.select { it.need == :heat && heats?(it, :aircon) }
                cools = rooms.select { it.need == :cool }
                if heats.any? && cools.any?
                    heats = heats.reject { heats?(it, :radiator) }
                end
                [heats, cools]
            end

            # Whether the strategy has one of room's `kind` of devices heat:
            # for units, one on this heat pump.
            def heats?(room, kind)
                targets = Strategy.heat(room, @settings)
                devices = if kind == :aircon
                              room.aircons.select { it.source == @name }
                          else
                              room.radiators
                          end
                devices.any? { targets[it.label] }
            end

            # The rooms needing what the direction does not give.
            def left_out(heats, cools)
                case @direction
                when :heat then cools
                when :cool then heats
                else heats + cools
                end
            end

            def choose(heats, cools)
                return if heats.empty? && cools.empty?
                heats.size >= cools.size ? :heat : :cool
            end

            # [room, unit] for a unit held by hand on this source, running
            # the other way from the direction the voting rooms gave it:
            # its own room did not vote, so it would otherwise go unsaid.
            def held_against(rooms)
                return [] unless @direction
                rooms.flat_map do |room|
                    room.held.grep(Aircon).select { it.source == @name }
                        .select { against?(it) }.map { [room, it] }
                end
            end

            def against?(unit)
                unit.on && Plan.direction_of(unit.mode) &&
                    Plan.direction_of(unit.mode) != @direction
            end
        end
    end
end
