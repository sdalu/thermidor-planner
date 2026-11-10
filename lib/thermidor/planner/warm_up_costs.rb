# frozen_string_literal: true

module Thermidor
    module Planner
        # Cheapest's warm-up, for WarmUp: each start from now to the
        # change, a cadence apart and no more than lead ahead, on
        # cheapest's devices and on quick's, summed in the room's own heat
        # capacity (°C of room) at each period's costs. Only the starts in
        # time count; the latest is the baseline, and an earlier or a quick
        # one wins only by the cost margin (StrategySettings#cost_margin).
        module WarmUpCosts
            # A start on a strategy's course, and what it costs.
            Option = Data.define(:start, :strategy, :course, :cost)

            private

            def costed(strategy, course)
                found = catch(:uncosted) { options(strategy, course) }
                return uncosted(strategy, course, found) if
                    found.is_a?(WarmUpPrices::Uncosted)
                return plain(strategy, course) if found.empty?
                chosen(found, strategy)
            end

            def uncosted(strategy, course, found)
                verdict = plain(strategy, course)
                return verdict unless verdict.due
                verdict.with(notes: [uncosted_note(found.label, found.minute),
                                     *verdict.notes])
            end

            def options(strategy, course)
                courses = { strategy => course }
                quick = quick_course(strategy) and courses[:quick] = quick
                starts.flat_map do |start|
                    courses.filter_map do |name, way|
                        next unless in_time?(way, start)
                        Option.new(start:, strategy: name, course: way,
                                   cost: cost(name, way, start, strategy))
                    end
                end
            end

            # Quick's course, when its devices differ and can be priced.
            def quick_course(strategy)
                key = key_of(labels(:quick, periods.first))
                return if key == key_of(labels(strategy, periods.first))
                return if key == :both &&
                          rates_for.values_at(:radiators, :units).any?(nil)
                course(:quick)
            end

            def starts
                first = [@ahead.minutes - lead, 0].max
                first = (first.fdiv(next_in).ceil * next_in)
                first.step(@ahead.minutes, next_in).to_a
            end

            # The baseline is the latest start on the strategy's own
            # devices, quick's only when its own are never in time.
            def chosen(found, strategy)
                latest = baseline(found, strategy)
                best = found.min_by do |option|
                    [option.cost, -option.start, -own_rank(option, strategy)]
                end
                pick = cheaper?(best, latest) ? best : latest
                return verdict_of(false, strategy) if pick.start >= next_in
                picked(pick, latest)
            end

            def baseline(found, strategy)
                own = found.select { it.strategy == strategy }
                (own.empty? ? found : own).max_by(&:start)
            end

            # 1 on the warm-up's own strategy, 0 on quick: ties go to it.
            def own_rank(option, strategy)
                option.strategy == strategy ? 1 : 0
            end

            def cheaper?(best, latest)
                margin = @context.strategy.cost_margin || 0.0
                best.cost < latest.cost &&
                    best.cost <= latest.cost * (1 - margin)
            end

            def picked(pick, latest)
                need = need(pick.course)
                notes = said(pick.strategy, pick.course, need)
                notes[0] = saving(pick, latest) if
                    pick != latest && need.finite?
                verdict_of(true, pick.strategy, need, notes)
            end

            # What the pick saves on the latest start, said.
            def saving(pick, latest)
                saved = (100 * (1 - pick.cost.fdiv(latest.cost))).round
                cheaper_note(pick.strategy, saved,
                             @ahead.minutes - latest.start)
            end

            # From now to the change: holding before the start (none while
            # coasting down to the band now) at the warm-up strategy's
            # costs, then the start's own until the change.
            def cost(name, way, start, strategy)
                reach = way.reached_at(start, before(start))
                (0...@ahead.minutes.ceil).sum do |minute|
                    payer = minute < start ? strategy : name
                    energy(minute, start, reach, way) *
                        price(payer, period_at(minute))
                end
            end

            # The heat in minute, °C of room.
            def energy(minute, start, reach, way)
                return holding(before(minute)) if minute < start
                trend = way.trend_at(minute)
                return 0.0 if trend.push.zero?
                return trend.push.abs / 60 if minute < reach
                kept_at(aim, trend.loss)
            end

            # Holding temperature against a loss, °C of room a minute.
            def kept_at(temperature, loss)
                [loss * sign * (temperature - outside), 0.0].max / 60
            end

            # Holding temperature at the band now, when it is there.
            def holding(temperature)
                now = @room.band&.public_send(@side)
                return 0.0 unless now && (sign * (now - temperature)) >= 0
                kept_at(temperature, ref_loss)
            end
        end
    end
end
