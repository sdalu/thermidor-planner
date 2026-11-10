# frozen_string_literal: true

module Thermidor
    module Planner
        # One change ahead, one side of its band (:heat, :cool), judged for
        # early start (design/early-start.md, its rules): whether it starts
        # now, on which strategy, and what is said. EarlyStart joins them.
        class WarmUp
            include WarmUpSets
            include WarmUpCosts
            include WarmUpPrices
            include EarlyNotes

            # What every warm-up of a step shares: EarlyStartSettings,
            # StrategySettings, the rates, the periods (from 0), the
            # minutes until the next plan.
            Context = Data.define(:settings, :strategy, :rates, :periods,
                                  :next_in)

            # due: whether it starts (or goes on) now; minutes: what
            # reaching the aim takes from now, nil without a rate.
            Verdict = Data.define(:ahead, :side, :due, :strategy, :minutes,
                                  :notes)

            def initialize(context, room, ahead, side)
                @context   = context
                @room      = room
                @ahead     = ahead
                @side      = side
                @t0        = room.temperature
                @started   = ahead.started
                @labels    = {}
                @radiators = room.radiators.map(&:label)
                @units     = room.aircons.map(&:label)
            end

            # The Verdict; nil when the room needs no early start for it.
            def verdict
                return unread if @t0.nil?
                if course_of_aim.reached?(@t0)
                    return held([]) if @started
                    return
                end
                judged(@started || own)
            end

            private

            # The heat side, else the band's only one.
            def first_side? = @side == :heat || @ahead.band.heat.nil?

            # Said once, on the first side; a started side is held.
            def unread
                return held([unread_note]) if first_side?
                held([]) if @started
            end

            def judged(strategy)
                course = course(strategy) or return unrated(strategy)
                return kept(strategy, course) if @started
                return costed(strategy, course) if cheapest?(strategy)
                plain(strategy, course)
            end

            def settings = @context.settings
            def next_in = @context.next_in
            def lead = settings.lead
            def zone = @room.zone

            # The band ahead's side, °C.
            def side = @ahead.band.public_send(@side)
            def sign = @side == :heat ? 1 : -1
            def aim = side - (sign * settings.reach)

            def course_of_aim = Course.new([], 0, aim, sign)

            def own
                settings.warmup == :own ? @ahead.strategy : settings.warmup
            end

            def rule(strategy)
                @context.strategy.rule(strategy) || Strategy::FALLBACK
            end

            def cheapest?(strategy)
                @side == :heat && rule(strategy) == :cheapest
            end

            def verdict_of(due, strategy, minutes = nil, notes = [])
                Verdict.new(ahead: @ahead, side: @side, due:, strategy:,
                            minutes:, notes:)
            end

            # Started, it goes on whatever could not be judged; else not.
            def held(notes)
                verdict_of(!@started.nil?, @started, nil, notes)
            end

            # Started, it is held, nothing said; else the fallback, or said.
            def unrated(strategy)
                return held([]) if @started
                return fallback(strategy) if settings.fallback
                held([unrated_note(said_set(strategy))])
            end

            def fallback(strategy)
                ahead_by = [settings.fallback, lead].min
                return verdict_of(false, strategy) if
                    @ahead.minutes - ahead_by > next_in
                verdict_of(true, strategy, nil, [fallback_note(ahead_by)])
            end

            def kept(strategy, course)
                need = need(course)
                verdict_of(true, strategy, need, said(strategy, course, need))
            end

            def plain(strategy, course)
                return verdict_of(false, strategy) unless due?(course)
                strategy, course, hurried = hurried(strategy, course)
                need = need(course)
                verdict_of(true, strategy, need,
                           [*hurried, *said(strategy, course, need)])
            end

            # Due when it is no more than lead ahead by the next plan, and
            # starting then would not be in time.
            def due?(course)
                return false if @ahead.minutes - lead > next_in
                !in_time?(course, next_in)
            end

            def in_time?(course, start)
                course.reached_at(start, before(start)) <= @ahead.minutes
            end

            # Minutes from now to the aim, started now.
            def need(course) = course.reached_at(0, @t0)

            def said(strategy, course, need)
                set = said_set(strategy)
                return [unreachable_note(set, outside)] if need.infinite?
                notes = [started_note(need, set, rate_now(course))]
                notes << late_note(need) if need > @ahead.minutes
                notes << capped_note(need) if need > lead
                notes
            end
        end
    end
end
