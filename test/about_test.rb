# frozen_string_literal: true

require "test_helper"

# What the planner says of itself matches what it does: devices ranked
# one by one; cheapest by the costs given, equal costs together, else
# the heat pumps, else the radiators.
class AboutTest < Minitest::Test
    include Thermidor::Planner

    GEMSPEC = File.expand_path("../thermidor-planner.gemspec", __dir__)

    def test_cheapest_says_its_fallbacks
        about = Strategy::ABOUT.fetch(:cheapest)
        assert about.start_with?("the cheapest source alone")
        assert_includes about, "equal costs together"
        assert_includes about, "else the heat pumps"
        assert about.end_with?("else the radiators")
    end

    def test_the_gemspec_says_devices_are_ranked_one_by_one
        spec = Gem::Specification.load(GEMSPEC)
        refute_includes spec.description, "device classes"
        assert_includes spec.description, "ranked one by one"
        assert_includes spec.description, "else the radiators"
    end
end
