# frozen_string_literal: true

require "test_helper"

# What the rules' effects do to the strategy's roles: a gas
# radiator and an electric unit, a 0.5 °C gap.
class EffectsTest < Minitest::Test
    include Thermidor::Planner

    ENERGIES = { radiator: "gas", aircon: "electricity" }.freeze
    COMFORT  = { radiator: 0.0, aircon: -0.5 }.freeze
    CHEAPEST = { radiator: nil, aircon: 0.0 }.freeze

    def test_none_changes_nothing
        assert_equal COMFORT, apply(Effects.none, COMFORT)
    end

    def test_preferred_leads_the_lead_backing_up
        prefer = effects(preferred: %w[electricity])
        assert_equal({ radiator: -0.5, aircon: 0.0 }, apply(prefer, COMFORT))
        both = { radiator: 0.0, aircon: 0.0 }
        assert_equal({ radiator: -0.5, aircon: 0.0 }, apply(prefer, both))
    end

    # The avoided lead backs up; a class with no part takes the lead.
    def test_avoided_never_leads
        avoid = effects(avoided: %w[electricity])
        assert_equal({ radiator: 0.0, aircon: -0.5 }, apply(avoid, CHEAPEST))
        assert_equal COMFORT, apply(avoid, COMFORT)
    end

    # Avoided alone, it still heats: there is nothing else to lead.
    def test_avoided_alone_still_leads
        avoid = effects(avoided: %w[electricity])
        assert_equal({ aircon: 0.0 }, apply(avoid, { aircon: 0.0 }))
    end

    def test_a_cap_limits_a_raise_lifts
        capped = effects(caps: { "gas" => 2.0 })
        assert_equal({ radiator: -2.0, aircon: -0.5 }, apply(capped, COMFORT))
        raised = effects(raises: { "electricity" => 1.0 })
        assert_equal({ radiator: 0.0, aircon: 1.0 }, apply(raised, COMFORT))
        assert_equal({ radiator: nil, aircon: 1.0 }, apply(raised, CHEAPEST))
    end

    # A raise on a gas radiator gives it a part cheapest had not.
    def test_a_raise_gives_a_part
        raised = effects(raises: { "gas" => 1.0 })
        assert_equal({ radiator: 1.0, aircon: 0.0 }, apply(raised, CHEAPEST))
    end

    # A room needs heat up to its band lifted by a raise on its energies.
    def test_a_raise_lifts_the_room_s_need
        assert_in_delta 1.0, effects(raises: { "electricity" => 1.0 })
            .lift(%w[gas electricity])
        assert_in_delta 0.0, effects(raises: { "electricity" => 1.0 })
            .lift(%w[gas])
    end

    private

    def effects(**)
        Effects.none.with(**)
    end

    def apply(effects, offsets)
        effects.apply(offsets, ENERGIES, 0.5)
    end
end
