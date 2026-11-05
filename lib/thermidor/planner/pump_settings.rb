# frozen_string_literal: true

module Thermidor
    module Planner
        # How a heat pump changes direction. switch: :heat, the most rooms
        # win and heat wins a tie; :hysteresis, a room asks for the
        # direction the pump does not run only once margin °C past its
        # band, and a tie keeps the direction it runs. A pump off is free
        # to go either way, with no margin.
        PumpSettings = Data.define(:switch, :margin) do
            def initialize(switch: :heat, margin: 0.5)
                raise ArgumentError, "unknown switch #{switch.inspect}" unless
                    PumpSettings::SWITCHES.include?(switch)
                raise ArgumentError, "negative margin #{margin}" if
                    margin.negative?
                super
            end

            def hysteresis? = switch == :hysteresis
        end

        class PumpSettings
            SWITCHES = %i[heat hysteresis].freeze
        end
    end
end
