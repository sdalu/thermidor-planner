# frozen_string_literal: true

require_relative "lib/thermidor/planner/version"

Gem::Specification.new do |s|
    s.name        = "thermidor-planner"
    s.version     = Thermidor::Planner::VERSION
    s.authors     = ["Stéphane D'Alu"]
    s.email       = ["sdalu@sdalu.com"]

    s.summary     = "What to tell a house's radiators and air conditioning " \
                    "so each room holds its comfort band"
    s.description = "From the band and strategy thermidor-schedule " \
                    "decides for each room, and what its devices read, " \
                    "the actions that bring them there: which devices " \
                    "heat, ranked one by one by the strategy over each " \
                    "one's capabilities (cheapest by the costs given, " \
                    "equal costs together, else the heat pumps, else the " \
                    "radiators), one direction for the units sharing a " \
                    "heat pump, targets on each device's step and " \
                    "range, devices " \
                    "held by hand kept apart from, and drifts from what " \
                    "was last set. It decides only; reading and writing " \
                    "the devices is the caller's."
    s.homepage    = "https://github.com/sdalu/thermidor-planner"
    s.license     = "MIT"

    s.required_ruby_version = ">= 3.4"

    s.metadata = {
        "homepage_uri" => s.homepage,
        "rubygems_mfa_required" => "true"
    }

    s.files = Dir.chdir(__dir__) do
        Dir["{lib}/**/*", "LICENSE.txt", "README.md"]
            .reject { |f| File.directory?(f) }
    end

    s.require_paths = ["lib"]

    s.add_dependency "thermidor-schedule", "~> 0.1"
end
