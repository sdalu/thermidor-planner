# frozen_string_literal: true

module Thermidor
    module Planner
        # The sentences of early start's notes (Start#notes), for WarmUp:
        # needs #zone, #side (the band ahead's side, °C), #lead and @ahead.
        module EarlyNotes
            private

            def note(kind, said)
                Notice.new("#{zone}: #{said}", kind:, zone:, ahead: @ahead)
            end

            def degrees(value) = format("%+.1f", value)
            def whole(minutes) = minutes.round.to_s
            def for_side = "early start for #{degrees(side)}"

            def started_note(need, set, rate)
                note(:early_start,
                     "#{for_side} in #{whole(@ahead.minutes)} min: needs " \
                     "#{whole(need)} (#{set}, #{format("%.1f", rate)} °C/h)")
            end

            def late_note(need)
                note(:early_late, "#{for_side} late: needs #{whole(need)} " \
                                  "min, #{whole(@ahead.minutes)} left")
            end

            def capped_note(need)
                note(:early_capped, "#{for_side} capped: needs " \
                                    "#{whole(need)} min, starts #{lead} ahead")
            end

            def unreachable_note(set, outside)
                note(:early_unreachable,
                     "#{degrees(side)} out of reach of #{set} at " \
                     "#{format("%.1f", outside)} °C outside: starts " \
                     "#{lead} ahead")
            end

            def hurry_note(strategy, need, quick)
                needs = need.finite? ? whole(need) : "more than #{lead}"
                note(:early_hurry, "#{for_side} on quick: #{strategy} " \
                                   "needs #{needs} min, quick #{whole(quick)}")
            end

            def fallback_note(minutes)
                note(:early_fallback, "#{for_side}, #{whole(minutes)} min " \
                                      "ahead (no rate, fallback)")
            end

            def cheaper_note(strategy, saved, than)
                quick = " on quick" if strategy == :quick
                note(:early_cheaper,
                     "#{for_side}#{quick}, #{whole(@ahead.minutes)} min " \
                     "ahead: #{saved} % cheaper than at #{whole(than)}")
            end

            def uncosted_note(label, minute)
                note(:early_uncosted, "#{for_side} by its rate: no cost for " \
                                      "#{label} at #{whole(minute)} min")
            end

            def unrated_note(set)
                why = set ? "no rate for #{set}" : "no device to reach it"
                note(:early_unrated,
                     "no early start for #{degrees(side)}: #{why}")
            end

            # Held, the warm-up goes on, and says so.
            def unread_note
                said = if @started then "#{for_side} held"
                       else "no early start for #{degrees(side)}"
                       end
                note(:early_unread, "#{said}: room temperature unknown")
            end
        end
    end
end
