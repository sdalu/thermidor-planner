# frozen_string_literal: true

require "test_helper"

# Devices ranked one by one, not by class: a room mixing quiet and loud,
# gentle and forced, gas and electric devices gets each its own part,
# whatever order they are listed in.
class DeviceRolesTest < Minitest::Test
    include Thermidor::Planner

    BAND = Thermidor::Schedule::Setpoint.new(heat: 20, cool: 26)
    Q  = RADIATOR_CAPS
    L  = Q.with(quiet: false)
    F  = Q.with(propagation: %w[forced])
    R  = Q.with(propagation: %w[radiation])
    E  = Q.with(energy: "electricity")
    U  = AIRCON_CAPS
    UQ = U.with(quiet: true)
    UR = U.with(propagation: %w[radiation])
    UG = U.with(energy: "gas")

    def test_quiet_keeps_the_quiet_radiator
        expect({ "valve:q" => 0.0, "valve:l" => nil },
               :quiet, valves(q: Q, l: L))
        expect({ "valve:q" => 0.0, "valve:l" => nil, "unit:1" => nil },
               :quiet, valves(l: L, q: Q), units(1 => U))
    end

    def test_a_quiet_unit_heats_beside_no_quiet_radiator
        expect({ "valve:l" => nil, "unit:1" => 0.0 },
               :quiet, valves(l: L), units(1 => UQ))
    end

    # Devices all of one kind have nothing to be ranked against.
    def test_one_kind_heats_whatever_the_strategy
        expect({ "valve:l" => 0.0 }, :quiet, valves(l: L))
        expect({ "valve:a" => 0.0, "valve:b" => 0.0 },
               :quiet, valves(a: L, b: L))
    end

    def test_comfort_leads_with_the_gentlest_device
        expect({ "valve:q" => 0.0, "valve:f" => -0.5, "unit:1" => -0.5 },
               :comfort, valves(q: Q, f: F), units(1 => U))
        expect({ "valve:f" => -0.5, "unit:1" => 0.0 },
               :comfort, valves(f: F), units(1 => UR))
    end

    def test_equally_gentle_devices_lead_together
        expect({ "valve:r" => 0.0, "unit:1" => 0.0 },
               :comfort, valves(r: R), units(1 => UR))
    end

    def test_cheapest_takes_the_heat_pumps_else_the_radiators
        expect({ "valve:q" => nil, "unit:1" => 0.0, "unit:2" => nil },
               :cheapest, valves(q: Q), units(1 => U, 2 => UG))
        expect({ "valve:q" => 0.0, "valve:l" => 0.0, "unit:1" => nil },
               :cheapest, valves(q: Q, l: L), units(1 => UG))
    end

    def test_quick_takes_every_device
        expect({ "valve:q" => 0.0, "valve:l" => 0.0, "unit:1" => 0.0 },
               :quick, valves(q: Q, l: L), units(1 => U))
    end

    def test_an_unread_device_takes_no_part
        loud = valve("l", L).with(mode: nil)
        assert_equal({ "valve:q" => 0.0 },
                     offsets(:quiet, [loud, valve("q", Q)], []))
    end

    def test_a_device_without_caps_follows_its_class_s_best
        expect({ "valve:q" => 0.0, "valve:x" => 0.0, "unit:1" => nil },
               :quiet, valves(q: Q, x: nil), units(1 => U))
    end

    def test_effects_go_by_each_device_s_energy
        prefer = Effects.none.with(preferred: %w[electricity])
        expect({ "valve:g" => -0.5, "valve:e" => 0.0, "unit:1" => 0.0 },
               :comfort, valves(g: Q, e: E), units(1 => U), effects: prefer)
        avoid = Effects.none.with(avoided: %w[gas])
        expect({ "valve:g" => -0.5, "valve:e" => 0.0, "unit:1" => -0.5 },
               :comfort, valves(g: Q, e: E), units(1 => U), effects: avoid)
    end

    # Every lead avoided: those not avoided nearest the lead lead, all
    # of them.
    def test_an_avoided_lead_hands_over_to_all_the_nearest
        avoid = Effects.none.with(avoided: %w[gas])
        expect({ "valve:g" => -0.5, "unit:1" => 0.0, "unit:2" => 0.0 },
               :comfort, valves(g: Q), units(1 => U, 2 => U), effects: avoid)
    end

    def test_raises_and_caps_go_by_each_device_s_energy
        raise_gas = Effects.none.with(raises: { "gas" => 1.0 })
        expect({ "valve:q" => 1.0, "valve:l" => 1.0, "unit:1" => 0.0 },
               :cheapest, valves(q: Q, l: L), units(1 => U),
               effects: raise_gas)
        cap_gas = Effects.none.with(caps: { "gas" => 2.0 })
        expect({ "valve:q" => -2.0, "valve:f" => -2.0, "unit:1" => -0.5 },
               :comfort, valves(q: Q, f: F), units(1 => U), effects: cap_gas)
    end

    private

    # The offsets for radiators and units, in their order and reversed.
    def expect(expected, strategy, radiators, aircons = [], effects: nil)
        [[radiators, aircons], [radiators.reverse, aircons.reverse]]
            .each do |valves, units|
                found = offsets(strategy, valves, units, effects:)
                assert_equal expected, found,
                             (valves + units).map(&:label).join(", ")
            end
    end

    def offsets(strategy, radiators, aircons, effects: nil)
        room = Room.new(zone: "hall", band: BAND, strategy:, radiators:,
                        aircons:, effects: effects || Effects.none)
        Roles.new(room, 20.0, [], room.effects)
             .offsets(strategy, StrategySettings.new)
    end

    def valves(**caps) = caps.map { |name, each| valve(name, each) }

    def valve(name, caps)
        Radiator.new(ref: name.to_s, label: "valve:#{name}", caps:,
                     temperature: nil, mode: :heat, target: 17.0,
                     range: 5.0..25.0, step: 0.5, least: 5.0)
    end

    def units(caps)
        caps.map do |id, each|
            Aircon.new(ref: id.to_s, label: "unit:#{id}", caps: each,
                       system: "h:1", source: "pump", master: id == 1,
                       temperature: nil, on: false, mode: :heat,
                       setpoint: 19.0, range: 15.0..30.0, step: 0.5)
        end
    end
end
