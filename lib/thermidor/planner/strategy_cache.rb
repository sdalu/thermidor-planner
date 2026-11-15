# frozen_string_literal: true

module Thermidor
    module Planner
        # A plan's Strategy.heat and Strategy.notes, each worked out once
        # per room: a room's Roles depend on the room and the settings
        # alone, while the plan asks again for each of its devices and each
        # action's why. Held by the room itself (identity): a room changed
        # with `with` is another room. What it hands out is frozen, shared
        # by every caller.
        class StrategyCache
            attr_reader :settings

            def initialize(settings = StrategySettings.new)
                @settings = settings
                @roles    = {}.compare_by_identity
                @heat     = {}.compare_by_identity
                @notes    = {}.compare_by_identity
            end

            # Strategy.heat(room, settings).
            def heat(room)
                @heat[room] ||=
                    Strategy.targets(room, roles(room), @settings).freeze
            end

            # Strategy.notes(room, settings).
            def notes(room)
                @notes[room] ||=
                    Strategy.overrides(room, roles(room), @settings).freeze
            end

            private

            # nil (no band heat side) is kept too.
            def roles(room)
                @roles.fetch(room) { @roles[room] = Strategy.roles_of(room) }
            end
        end
    end
end
