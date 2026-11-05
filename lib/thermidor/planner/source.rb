# frozen_string_literal: true

module Thermidor
    module Planner
        # The one direction (:heat, :cool, or nil to stay off) of a heat
        # pump shared by `rooms`, from what they need, a room needing heat
        # counting only when its unit may heat it, one needing cool only
        # when its unit can cool: on a conflict, rooms
        # needing heat that have radiators to give it drop out; then the
        # most rooms win, heat on a tie. With no need either way, the
        # direction it has (`current`) stays. With hysteresis (the
        # settings' pump, PumpSettings), a room counts for the direction
        # the pump does not run only once a margin past its band, and a
        # tie keeps it; every room needing the other way is said all the
        # same. A direction set outside the planner and held (held: :heat,
        # :cool or nil for neither) wins; the rooms it does not serve are
        # said. A unit of a system set aside is not given it: Plan leaves
        # it out of the rooms (PumpPlan#source).
        class Source
            # Nothing held.
            FREE = Object.new.freeze

            # name: the heat pump's, as its units' source gives it;
            # stepped: the rooms needing heat that stepped aside on a
            # conflict, for their radiators to heat.
            attr_reader :name, :direction, :unserved, :overridden, :stepped

            # current: the direction its systems run now; state: what the
            # caller knows of it (PumpState): a direction held, whether its
            # compressor runs.
            def initialize(name, rooms, current,
                           settings = StrategySettings.new,
                           state: PumpState.new)
                @name     = name
                @settings = settings
                @pump     = settings.pump
                @current  = current
                @running  = running?(state, rooms)
                vote(state.held, rooms)
            end

            def to_s = @name.to_s

            private

            def vote(held, rooms)
                voters = voters(rooms)
                @direction  = directed(held, voters)
                @unserved   = left_out(*votes(voters))
                @stepped    = stepped_aside(voters)
                @overridden = held_against(rooms)
            end

            def directed(held, voters)
                held.equal?(FREE) ? chosen(voters) : held
            end

            # Its compressor running, as the caller says, else one of its
            # units on.
            def running?(state, rooms)
                return state.running unless state.running.nil?
                rooms.flat_map { it.aircons + it.held.grep(Aircon) }
                     .any? { it.source == @name && it.on }
            end

            # The rooms with a unit of their own on this source: one held
            # off by hand does not vote, nor does one unread (nil mode):
            # it cannot be known to want either direction.
            def voters(rooms)
                rooms.select { |room| voting?(room) }
            end

            def voting?(room) = own(room).any?(&:mode)

            # room's units on this heat pump.
            def own(room) = room.aircons.select { it.source == @name }

            # [rooms needing heat, rooms needing cool] that a unit on this
            # pump may serve, the rooms stepping aside on a conflict left
            # out; margin: with the pump's hysteresis against the
            # direction it runs.
            def votes(rooms, margin: false)
                heats, cools = wanting(rooms, margin)
                heats = heats.reject { radiators?(it) } if
                    heats.any? && cools.any?
                [heats, cools]
            end

            # The rooms needing heat that step aside on a conflict.
            def stepped_aside(rooms)
                heats, cools = wanting(rooms, false)
                return [] if heats.empty? || cools.empty?
                heats.select { radiators?(it) }
            end

            def wanting(rooms, margin)
                [rooms.select { needs?(it, :heat, margin) && heats?(it) },
                 rooms.select { needs?(it, :cool, margin) && cools?(it) }]
            end

            # Whether room has radiators able to heat it to its band, the
            # strategy aside: they heat it when it steps aside.
            def radiators?(room)
                heat = room.band&.heat or return false
                room.radiators.any? { Roles.able?(it, room.excluded, heat) }
            end

            # Whether the strategy has one of room's units on this heat
            # pump heat.
            def heats?(room)
                targets = Strategy.heat(room, @settings)
                own(room).any? { targets[it.label] }
            end

            # Whether room has a unit of its own on this heat pump, read,
            # that can cool it.
            def cools?(room)
                own(room).any? { it.mode && Roles.cools?(it) }
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

            # Whether hysteresis holds the pump to a direction it runs: a
            # compressor stopped, its system's mode kept, holds none.
            def holding? = @pump.hysteresis? && !@current.nil? && @running

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
