# frozen_string_literal: true

require "test_helper"

# The strategies' rules follow the capabilities, not the device names.
class RolesTest < Minitest::Test
    include Thermidor::Planner

    RADIATOR = RADIATOR_CAPS
    AIRCON   = AIRCON_CAPS
    BAND     = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 24)

    def test_comfort_leads_with_the_gentlest
        assert_equal({ radiator: 0.0, aircon: -0.5 }, offsets(:comfort))
        forced  = RADIATOR.with(propagation: %w[forced])
        radiant = AIRCON.with(propagation: %w[radiation])
        swapped = offsets(:comfort, radiator: forced, aircon: radiant)
        assert_equal({ radiator: -0.5, aircon: 0.0 }, swapped)
    end

    def test_quiet_keeps_the_quiet_ones
        assert_equal({ radiator: 0.0, aircon: nil }, offsets(:quiet))
        quiet_ac = offsets(:quiet, aircon: AIRCON.with(quiet: true))
        assert_equal({ radiator: 0.0, aircon: 0.0 }, quiet_ac)
    end

    def test_cheapest_prefers_a_heat_pump
        assert_equal({ radiator: nil, aircon: 0.0 }, offsets(:cheapest))
        gas_ac = offsets(:cheapest, aircon: AIRCON.with(energy: "gas"))
        assert_equal({ radiator: 0.0, aircon: nil }, gas_ac)
    end

    def test_a_class_that_cannot_heat_takes_no_part
        cold = offsets(:quick, aircon: AIRCON.with(heat: false))
        assert_equal({ radiator: 0.0 }, cold)
    end

    # An unread device (nil mode, as a caller leaves one) takes no part
    # on its own: its class is left out, as if the room had none of it,
    # not decided by its caps alone.
    def test_an_unread_device_alone_cannot_make_its_class_able
        unread = device(Aircon, AIRCON).with(mode: nil)
        room = Room.new(zone: "z", band: BAND, strategy: :quick,
                        radiators: [device(Radiator, RADIATOR)],
                        aircons: [unread])
        offsets = Roles.new(room, 20.0).offsets(:quick, StrategySettings.new)
        assert_equal({ radiator: 0.0 }, offsets)
    end

    # Read and unread devices of the same class: the read one still
    # decides it.
    def test_a_read_device_still_decides_its_class_with_an_unread_one
        unread = device(Aircon, AIRCON).with(mode: nil)
        read = device(Aircon, AIRCON)
        room = Room.new(zone: "z", band: BAND, strategy: :quick,
                        radiators: [device(Radiator, RADIATOR)],
                        aircons: [unread, read])
        offsets = Roles.new(room, 20.0).offsets(:quick, StrategySettings.new)
        assert_equal({ radiator: 0.0, aircon: 0.0 }, offsets)
    end

    # What a strategy uses of the classes, by class, the lead first;
    # naming the systems behind them is the caller's.
    def test_uses_names_the_classes_the_lead_first
        caps = { radiator: RADIATOR, aircon: AIRCON }
        assert_equal [[:radiator, 0.0], [:aircon, -0.5]],
                     Strategy.uses(:comfort, StrategySettings.new, caps)
        assert_equal [[:aircon, 0.0]],
                     Strategy.uses(:cheapest, StrategySettings.new, caps)
    end

    private

    def offsets(strategy, radiator: RADIATOR, aircon: AIRCON)
        room = Room.new(zone: "z", band: BAND, strategy:,
                        radiators: [device(Radiator, radiator)],
                        aircons: [device(Aircon, aircon)])
        Roles.new(room, 20.0).offsets(strategy, StrategySettings.new)
    end

    # A device read: mode :heat, nothing else said, so the class's part
    # is decided by caps and range alone, not by this helper's fields.
    def device(type, caps)
        type.new(**type.members.to_h { [it, nil] }, mode: :heat, caps:)
    end
end
