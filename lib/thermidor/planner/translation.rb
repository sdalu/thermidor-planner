# frozen_string_literal: true

module Thermidor
    module Planner
        # A device's target or setpoint, and the gap added to the band's
        # side to get it (nil: none).
        Target = Data.define(:celsius, :gap)

        # The translation Plan uses unless given one: every target as the
        # band's. A translation makes a room's setpoint into what a
        # device's own sensor reads when the room holds it; it answers
        # target(room, device, setpoint, mode) with a Target, device being
        # the Radiator or Aircon asked for and mode the unit's direction
        # (:heat, :cool, nil for a radiator), and notes, what it could not
        # translate, said once.
        class AsIs
            def target(_room, _device, setpoint, _mode = nil)
                Target.new(celsius: setpoint, gap: nil)
            end

            def notes = []
        end
    end
end
