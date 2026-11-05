# frozen_string_literal: true

module Thermidor
    module Planner
        # What Plan says of a heat pump (Notice): the rooms it does not
        # serve, a unit held by hand against it, a system left in auto.
        module PumpNotices
            private

            # The rooms needing what the pump does not give, said; one
            # needing heat is cut from it, for its radiators (#uncut).
            def unserved(source)
                source.unserved.each do |room|
                    @cut[room.zone] << source.name if room.need == :heat
                    notice("#{room.zone}: needs #{room.need}, but " \
                           "#{source} #{source.direction || "stays off"}",
                           kind: :unserved, zone: room.zone,
                           source: source.name)
                end
            end

            # A unit held by hand on a source whose other rooms just gave
            # it the other direction: its own room did not vote, so it
            # would otherwise lose its hand silently.
            def held_against(source)
                source.overridden.each do |room, unit|
                    was = Plan::DOING.fetch(Plan.direction_of(unit.mode))
                    now = Plan::DOING.fetch(source.direction)
                    notice("#{room.zone}: #{unit.label} held #{was}, the " \
                           "heat pump goes #{now}",
                           kind: :held_against, zone: room.zone,
                           device: unit.label, source: source.name)
                end
            end

            def left_in_auto(source, master)
                return unless master.mode == :auto
                notice("#{master.system}: left in auto: the heat pump " \
                       "#{source} has no direction now",
                       kind: :left_in_auto, device: master.system,
                       source: source.name)
            end
        end
    end
end
