# frozen_string_literal: true

require "test_helper"

# A predicate answers true or false, never nil: caps that do not say
# whether a device heats are a no.
class PredicateTest < Minitest::Test
    include Thermidor::Planner

    Device = Struct.new(:caps, :label, :mode)

    def test_heats_is_false_when_the_caps_do_not_say
        unsaid = Device.new(RADIATOR_CAPS.with(heat: nil), "v", :heat)
        assert_equal false, Roles.heats?(unsaid, [])
        assert_equal false, Roles.heats?(Device.new(nil, "v", :heat), [])
        assert_equal true, Roles.heats?(Device.new(RADIATOR_CAPS, "v", :heat),
                                        [])
    end
end
