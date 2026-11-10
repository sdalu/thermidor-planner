# frozen_string_literal: true

module Thermidor
    module Planner
        # A warm-up's devices and their rates, for WarmUp: which devices a
        # strategy heats with in a period, the set they make (:radiators,
        # :units, :both), its Rise, and the Course they give.
        module WarmUpSets
            private

            # The labels of the devices the strategy has heat at the band
            # ahead in period, less those an energy rule caps under the aim.
            def labels(strategy, period)
                @labels[[strategy, period]] ||= begin
                    room = @room.with(band: @ahead.band, strategy:,
                                      costs: period.costs,
                                      excluded: period.excluded)
                    Strategy.heat(room, @context.strategy)
                            .filter_map do |label, target|
                        label if target && !capped?(label)
                    end
                end
            end

            def capped?(label)
                device = (@room.radiators + @room.aircons)
                         .find { it.label == label }
                cap = @room.effects.caps[device&.caps&.energy]
                !cap.nil? && cap > settings.reach
            end

            def key_of(found)
                radiators = found.any? { @radiators.include?(it) }
                units = found.any? { @units.include?(it) }
                return :both if radiators && units
                return :radiators if radiators
                :units if units
            end

            # The set a strategy warms up with now, as said.
            def said_set(strategy)
                return ("units" if cooling_units.any?) if @side == :cool
                key_of(labels(strategy, periods.first))&.to_s
            end

            # The set's Rise; for :both without one, the faster single.
            def rise(key)
                return unless key
                rates_for[key] || (faster if key == :both)
            end

            def faster
                rates_for.values_at(:radiators, :units).compact.max_by do |one|
                    one.base - (one.loss * (@t0 - outside))
                end
            end

            def rates_for
                (@context.rates || {}).fetch(@side, nil) || {}
            end

            # The outside °C: the room's, else the rates' learned gap
            # under the room, else the room's own.
            def outside
                @outside ||= @room.outside ||
                             (reference&.gap && (@t0 - reference.gap)) || @t0
            end

            def reference = rates_for.values.first
            def ref_loss = reference&.loss || 0.0

            # The way a strategy's devices bring the room to the aim, nil
            # when they have no rate now.
            def course(strategy)
                @side == :heat ? heat_course(strategy) : cool_course
            end

            def heat_course(strategy)
                first = rise(key_of(labels(strategy, periods.first))) or
                    return
                pieces = periods.map do |period|
                    [period.minutes,
                     trend(rise(key_of(labels(strategy, period))))]
                end
                Course.new(pieces, first.delay, aim, sign)
            end

            def cool_course
                found = (rates_for[:units] if cooling_units.any?) or return
                Course.new([[0, trend(found)]], found.delay, aim, sign)
            end

            def cooling_units
                @room.aircons.select { it.mode && Roles.cools?(it) }
            end

            # A set's Trend; none, the room coasting.
            def trend(found)
                return Trend.new(push: 0.0, loss: ref_loss, outside:) unless
                    found
                Trend.new(push: sign * found.base, loss: found.loss, outside:)
            end

            def periods = @context.periods

            # A late or capped warm-up on quick's devices, when hurry is
            # on and they are faster: [strategy, course, its note or none].
            def hurried(strategy, course)
                need = need(course)
                return [strategy, course] unless hurry?(strategy, need)
                quick = course(:quick)
                quick_need = quick && need(quick)
                return [strategy, course] unless
                    quick_need && quick_need < need
                [:quick, quick, hurry_note(strategy, need, quick_need)]
            end

            def hurry?(strategy, need)
                settings.hurry && @side == :heat &&
                    rule(strategy) != :quick &&
                    (need > @ahead.minutes || need > lead)
            end

            def rate_now(course)
                trend = course.trend_at(0)
                (trend.push - (trend.loss * (@t0 - trend.outside))).abs
            end

            # The room's temperature at minute start, before starting:
            # coasting down to the band now (cooling: up to it) when past
            # it, else as it is.
            def before(start)
                now = @room.band&.public_send(@side)
                return @t0 if now && (sign * (now - @t0)) >= 0
                coasted = Trend.new(push: 0.0, loss: ref_loss, outside:)
                               .after(@t0, start / 60.0)
                return coasted unless now
                sign.positive? ? [coasted, now].max : [coasted, now].min
            end
        end
    end
end
