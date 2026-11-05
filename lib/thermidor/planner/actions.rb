# frozen_string_literal: true

module Thermidor
    module Planner
        # The actions of a plan as they are found, each with why: a
        # room's strategy, what overrode it (Strategy.notes, and those
        # noted of the device, a heat pump's), its band and temperature,
        # and for a target or setpoint the translation's offset; a heat
        # pump's mode, its source.
        class Actions
            def initialize(settings = StrategySettings.new)
                @settings = settings
                @list     = []
                @notes    = {}
            end

            def to_a = @list.dup

            # notes: { [zone, device label] => [what overrode the room's
            # strategy for that device], ... } (PumpCycle#notes).
            def noted(notes) = @notes.merge!(notes)

            def change(room, device, setting, from, to)
                @list << Action.new(zone: room.zone, device:, setting:, from:,
                                    to:, why: why(room, device))
            end

            # A target or setpoint (Target), its gap said.
            def retarget(room, device, setting, from, target)
                gap = target.gap
                offset = format(", %+.1f offset", gap) if gap
                @list << Action.new(zone: room.zone, device:, setting:, from:,
                                    to: target.celsius, offset: gap,
                                    why: "#{why(room, device)}#{offset}")
            end

            # A system's mode, set for its heat pump.
            def mode(device, from, to, source)
                @list << Action.new(zone: nil, device:, setting: :mode, from:,
                                    to:, why: "source #{source}")
            end

            private

            def why(room, device)
                reading = ", at #{room.reading}" if room.reading
                said = [room.strategy, *Strategy.notes(room, @settings),
                        *@notes[[room.zone, device]], room.band]
                "#{said.join(", ")}#{reading}"
            end
        end
    end
end
