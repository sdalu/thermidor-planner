# frozen_string_literal: true

module Thermidor
    module Planner
        # The one direction (:heat, :cool, or nil to stay off) of a heat
        # pump shared by `rooms`, from what they need, a room needing heat
        # counting only when its unit may heat it: on a conflict, rooms
        # needing heat that have radiators to give it drop out; then the
        # most rooms win, heat on a tie. With no need either way, the
        # direction it has (`current`) stays. With hysteresis (the
        # settings' pump, PumpSettings), a room counts for the direction
        # the pump does not run only once a margin past its band, and a
        # tie keeps it; every room needing the other way is said all the
        # same. A direction set outside the planner and held (held: :heat,
        # :cool or nil for neither) wins; the rooms it does not serve are
        # said.
        class Source
            # Nothing held.
            FREE = Object.new.freeze

            # name: the heat pump's, as its units' source gives it.
            attr_reader :name, :direction, :unserved, :overridden

            def initialize(name, rooms, current,
                           settings = StrategySettings.new, held: FREE)
                @name     = name
                @settings = settings
                @pump     = settings.pump
                @current  = current
                voters = voters(rooms)
                @direction  = held.equal?(FREE) ? chosen(voters) : held
                @unserved   = left_out(*votes(voters))
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

            # [rooms needing heat, rooms needing cool]; margin: with the
            # pump's hysteresis against the direction it runs.
            def votes(rooms, margin: false)
                heats = rooms.select do |room|
                    needs?(room, :heat, margin) && heats?(room, :aircon)
                end
                cools = rooms.select { needs?(it, :cool, margin) }
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

            # The direction the voters give, or the current one when they
            # give none.
            def chosen(voters)
                choose(*votes(voters, margin: true)) || @current
            end

            def choose(heats, cools)
                return if heats.empty? && cools.empty?
                return @current if holding? && heats.size == cools.size
                heats.size >= cools.size ? :heat : :cool
            end

            # Whether hysteresis holds the pump to a direction it runs.
            def holding? = @pump.hysteresis? && !@current.nil?

            # Whether room needs direction: past its band, by the margin
            # when asked and the pump runs the other way.
            def needs?(room, direction, margin)
                return room.need == direction unless
                    margin && holding? && direction != @current
                past?(room, direction, @pump.margin)
            end

            def past?(room, direction, margin)
                now = room.temperature or return false
                band = room.band or return false
                if direction == :heat
                    band.heat && now < band.heat + room.lift - margin
                else
                    band.cool && now > band.cool + margin
                end
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
