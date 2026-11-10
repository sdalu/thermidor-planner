# frozen_string_literal: true

module Thermidor
    module Planner
        # Early start (design/early-start.md): whether a room starts a
        # change ahead of its time, so it is in the band at the change, with
        # which band and strategy, and what is said. Without a clock: the
        # caller gives the minutes until each change and until the next
        # plan, the rates it learned and the latch it keeps (Ahead#started).
        class EarlyStart
            def initialize(settings: EarlyStartSettings.new,
                           strategy: StrategySettings.new)
                @settings = settings
                @strategy = strategy
            end

            # room: the Room the plan would get; ahead: [Ahead, ...]; rates:
            # { heat: { radiators:, units:, both: }, cool: { units: } }, Rises,
            # any missing; next_in: minutes until the next plan; periods:
            # [Period, ...] over the warm-up, nil for now's alone.
            def start(room, ahead:, rates:, next_in:, periods: nil)
                raise ArgumentError, "next_in #{next_in} is not positive" unless
                    next_in.positive?
                context = WarmUp::Context.new(
                    settings: @settings, strategy: @strategy, rates:,
                    periods: periods_of(room, periods), next_in:
                )
                joined(room, verdicts(context, room, ahead))
            end

            private

            def verdicts(context, room, ahead)
                ahead.flat_map do |one|
                    sides(room, one).filter_map do |side|
                        WarmUp.new(context, room, one, side).verdict
                    end
                end
            end

            # The sides of a change's band asking more than the band now: a
            # higher heat side, a lower cool side.
            def sides(room, ahead)
                now = room.band
                [(:heat if more?(ahead.band.heat, now&.heat, 1)),
                 (:cool if more?(ahead.band.cool, now&.cool, -1))].compact
            end

            # Whether side ahead asks more than side now, sign +1 for a
            # heat side (higher), -1 for a cool one (lower).
            def more?(ahead, now, sign)
                return false if ahead.nil?
                now.nil? || (sign * (ahead - now)).positive?
            end

            def periods_of(room, periods)
                now = Period.new(minutes: 0, costs: room.costs,
                                 excluded: room.excluded)
                return [now] if periods.nil? || periods.empty?
                sorted = periods.sort_by(&:minutes)
                sorted.first.minutes.positive? ? [now, *sorted] : sorted
            end

            def joined(room, verdicts)
                notes = verdicts.flat_map(&:notes)
                due = verdicts.select(&:due)
                driver = driver(due) or
                    return Start.new(band: room.band, strategy: room.strategy,
                                     ahead: nil, minutes: nil, notes:)
                Start.new(band: band(room, due, driver),
                          strategy: driver.strategy, ahead: driver.ahead,
                          minutes: driver.minutes, notes:)
            end

            # The due warm-up driving: the highest heat side, the nearer on
            # a tie; else the lowest cool side.
            def driver(due)
                heat = due.select { it.side == :heat }
                if heat.any?
                    return heat.max_by do |one|
                        [one.ahead.band.heat, -one.ahead.minutes]
                    end
                end
                due.min_by { [it.ahead.band.cool, it.ahead.minutes] }
            end

            # The band now, each side moved to the most demanding due one's;
            # the driver's whole when the sides come closer than the
            # deadband.
            def band(room, due, driver)
                now = room.band
                heat = [now&.heat, *sided(due, :heat)].compact.max
                cool = [now&.cool, *sided(due, :cool)].compact.min
                return Schedule::Setpoint.new(heat:, cool:) unless now
                now.with(heat:, cool:)
            rescue Schedule::Error
                driver.ahead.band
            end

            def sided(due, side)
                due.select { it.side == side }
                   .map { it.ahead.band.public_send(side) }
            end
        end
    end
end
