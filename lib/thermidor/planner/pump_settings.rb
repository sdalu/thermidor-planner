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
        #   started only once a room on it is wait °C under its
        #   unit's target, its units on together, and stopped once no
        #   room is under it, its units off together;
        # - min_on, min_off (minutes): a pump started (stopped) less than
        #   that ago has none of its units switched off (on), unless a
        #   unit's energy is excluded now, it runs another direction, or
        #   its room is urgent °C past its band the other way;
        # - backup_above (°C): with the outside at or above it, a room less
        #   than backup_within °C under its band heats with its radiators, its
        #   units a comfort gap behind, whatever the strategy; a room
        #   whose radiators led last (Room#led) keeps them leading until
        #   the outside falls backup_kept °C below it;
        # - backup_under (°C): while a pump heating waits, mild and
        #   stopped with no room calling, a radiator its room's strategy
        #   steps back behind the unit heats no higher than that under
        #   the pump's restart point (the unit's target less wait °C), so
        #   the pump starts first (PumpWait).
        PUMP_DEFAULTS = { switch: :heat, margin: 0.5, wait_above: nil,
                          wait: 1.0, min_on: nil, min_off: nil,
                          urgent: 1.0, backup_above: nil, backup_within: 1.0,
                          backup_kept: 0.5, backup_under: 0.5 }.freeze

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
            def wait?(outside)
                !wait_above.nil? && !outside.nil? && outside >= wait_above
            end

            # Whether outside is mild for the radiators to lead: from
            # backup_above, and backup_kept below it for radiators leading
            # already (leading).
            def backup?(outside, leading: false)
                bound = backup_bound(leading:) or return false
                !outside.nil? && outside >= bound
            end

            # The outside °C from which the radiators lead, nil when off.
            def backup_bound(leading: false)
                return if backup_above.nil?
                leading ? backup_above - backup_kept : backup_above
            end
        end

        class PumpSettings
            SWITCHES = %i[heat hysteresis].freeze

            # Settings with no off: nil is refused.
            REQUIRED = %i[margin wait urgent backup_within
                          backup_kept].freeze

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
