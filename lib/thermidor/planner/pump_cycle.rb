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
            include LeastTimes

            # A unit left as it is: power and setpoint unwritten.
            KEEP = Object.new.freeze

            # entries: [[room, unit, target or nil], ...], the pump's units
            # planned; state: its PumpState, nil unknown.
            # outsides: the outside °C given by the rooms on the pump, its
            # units planned or not; nil, those of the entries' rooms.
            def initialize(source, entries, settings, state, outsides: nil)
                @source    = source
                @entries   = entries
                @settings  = settings
                @state     = state || PumpState.new
                @outsides  = outsides
                @warnings  = []
                @notes     = {}
                @waits     = {}
            end

            # warnings: what it said; rested: the zones needing heat whose
            # units it holds while the pump rests, for their radiators;
            # notes: { [zone, unit label] => [what overrode its room's
            # strategy, for why], ... }, after #targets; waits: { zone =>
            # its units' highest target } while the pump waits, mild and
            # stopped with no room calling, after #targets.
            attr_reader :warnings, :notes, :waits

            def rested = @rested || []

            # { [zone, unit label] => target, nil or KEEP }.
            def targets
                found = wait? ? gapped : @entries
                held(found).to_h do |room, unit, target|
                    [[room.zone, unit.label], target]
                end
            end

            private

            def direction = @source.direction

            def running?
                return @state.running == true unless @state.running.nil?
                @entries.any? { |_, unit, _| unit.on }
            end

            # Mild weather, heating, every room's temperature known: mild
            # by every room on the pump that gives an outside temperature,
            # one at least giving one.
            def wait?
                return false unless direction == :heat
                outsides = @outsides ||
                           @entries.filter_map { |room, _, _| room.outside }
                outsides.any? && outsides.all? { @settings.wait?(it) } &&
                    @entries.all? { |room, _, _| room.temperature }
            end

            # Running, until no room is under its unit's target, then every
            # unit off together; stopped, until a room is wait
            # under it, then every unit whose room is under its target on
            # together. A unit whose room is not under its target is off,
            # the others carrying the run.
            def gapped
                margin = running? ? 0.0 : @settings.wait
                calls = calls?(margin)
                wait unless calls || running?
                @entries.map { gap(*it, calls) }
            end

            # A unit on while the pump calls and its room is under its
            # target; else off, said when the strategy had it heat.
            def gap(room, unit, target, calls)
                return [room, unit, target] if
                    calls && under?(room, target, 0.0)
                note(room, unit, "pump wait") if target
                [room, unit, nil]
            end

            def calls?(margin)
                @entries.any? { |room, _, target| under?(room, target, margin) }
            end

            def wait
                @entries.each do |room, _, target|
                    next unless target
                    @waits[room.zone] = [@waits[room.zone], target].compact.max
                end
            end

            def note(room, unit, said)
                (@notes[[room.zone, unit.label]] ||= []) << said
            end

            def under?(room, target, margin)
                !target.nil? && room.temperature < target - margin
            end
        end
    end
end
