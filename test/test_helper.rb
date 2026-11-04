# frozen_string_literal: true

require "minitest/autorun"

require "thermidor/planner"

# What a device can do, as the planner reads it (Planner's caps).
Caps = Data.define(:heat, :cool, :quiet, :energy, :propagation)

# A thermostat on a gas radiator: heats only, quietly, by convection
# and radiation.
RADIATOR_CAPS = Caps.new(heat: true, cool: false, quiet: true,
                         energy: "gas",
                         propagation: %w[convection radiation])

# A unit on an electric heat pump: heats and cools, by forced air.
AIRCON_CAPS = Caps.new(heat: true, cool: true, quiet: false,
                       energy: "electricity", propagation: %w[forced])
