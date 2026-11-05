# frozen_string_literal: true

module Thermidor
    module Planner
        # How a heat pump is run. switch: :heat, the most rooms win and
        # heat wins a tie; :hysteresis, a room asks for the direction the
        # pump does not run only once margin °C past its band, and a tie
        # keeps the direction it runs; a pump off goes either way with no
        # margin.
        #
        # Against short cycles, judged per heat pump (PumpCycle), its one
        # compressor running while any unit calls; each off while nil:
        # - mild (°C): with the outside at or above it, a pump heating is
        #   started only once a room on it is mild_deadband °C under its
        #   unit's target, its units on together, and stopped once no
        #   room is under it, its units off together;
        # - min_on, min_off (minutes): a pump started (stopped) less than
        #   that ago has none of its units switched off (on), unless a
        #   unit's energy is excluded now, it runs another direction, or
        #   its room is urgent °C past its band the other way;
        # - mild_lead (°C): with the outside at or above it, a room less
        #   than lead_gap °C under its band heats with its radiators, its
        #   units a comfort gap behind, whatever the strategy; a room
        #   whose radiators led last (Room#led) keeps them leading until
        #   the outside falls lead_deadband °C below it.
        PUMP_DEFAULTS = { switch: :heat, margin: 0.5, mild: nil,
                          mild_deadband: 1.0, min_on: nil, min_off: nil,
                          urgent: 1.0, mild_lead: nil, lead_gap: 1.0,
                          lead_deadband: 0.5 }.freeze

        PumpSettings = Data.define(*PUMP_DEFAULTS.keys) do
            def initialize(**given)
                values = PUMP_DEFAULTS.merge(given)
                switch = values[:switch]
                raise ArgumentError, "unknown switch #{switch.inspect}" unless
                    PumpSettings::SWITCHES.include?(switch)
                PumpSettings.given(values)
                PumpSettings.positive(**values.except(:switch))
                super(**values)
            end

            def hysteresis? = switch == :hysteresis

            # Whether outside (°C, nil unknown) is mild for the gap.
            def mild?(outside) = !mild.nil? && !outside.nil? && outside >= mild

            # Whether outside is mild for the radiators to lead: from
            # mild_lead, and lead_deadband below it for radiators leading
            # already (leading).
            def lead?(outside, leading: false)
                bound = lead_bound(leading:) or return false
                !outside.nil? && outside >= bound
            end

            # The outside °C from which the radiators lead, nil when off.
            def lead_bound(leading: false)
                return if mild_lead.nil?
                leading ? mild_lead - lead_deadband : mild_lead
            end
        end

        class PumpSettings
            SWITCHES = %i[heat hysteresis].freeze

            # Settings with no off: nil is refused.
            REQUIRED = %i[margin mild_deadband urgent lead_gap
                          lead_deadband].freeze

            def self.given(values)
                missing = REQUIRED.select { values[it].nil? }
                raise ArgumentError, "no #{missing.join(", ")}" if
                    missing.any?
            end

            # Refuses a negative value among those given (nil: unset).
            def self.positive(**values)
                values.each do |name, value|
                    raise ArgumentError, "negative #{name} #{value}" if
                        value&.negative?
                end
            end
        end
    end
end
