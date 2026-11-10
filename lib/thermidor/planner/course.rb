# frozen_string_literal: true

module Thermidor
    module Planner
        # A warm-up's way to its aim: pieces, [[from minute, Trend], ...]
        # from 0, each holding until the next, the last on; delay, the
        # minutes from its start before the room moves; sign, +1 heating
        # (the aim reached from below), -1 cooling.
        class Course
            attr_reader :pieces, :delay

            def initialize(pieces, delay, aim, sign)
                @pieces = pieces
                @delay  = delay
                @aim    = aim
                @sign   = sign
            end

            def reached?(temperature) = (@sign * (@aim - temperature)) <= 0

            # The minute (from now) the room reaches the aim, started at
            # minute start from temperature; INFINITY when it never does.
            def reached_at(start, temperature)
                return start.to_f if reached?(temperature)
                at = start + @delay
                spans(at).each do |trend, ending|
                    hours = trend.hours_to(temperature, @aim)
                    reach = hours && (at + (hours * 60))
                    return reach if reach && reach <= ending
                    return Float::INFINITY if ending.infinite?
                    temperature = trend.after(temperature, (ending - at) / 60.0)
                    at = ending
                end
            end

            # The Trend at minute.
            def trend_at(minute)
                @pieces.reverse.find { |from, _| from <= minute }&.last ||
                    @pieces.first.last
            end

            private

            # [[trend, its end minute], ...] of the pieces from minute at on.
            def spans(at)
                ends = @pieces.drop(1).map(&:first) + [Float::INFINITY]
                @pieces.map(&:last).zip(ends)
                       .reject { |_, ending| ending <= at }
            end
        end
    end
end
