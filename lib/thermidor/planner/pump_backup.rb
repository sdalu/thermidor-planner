# frozen_string_literal: true

module Thermidor
    module Planner
        # The radiators leading in mild weather (PumpSettings backup_above),
        # for Roles: with the outside mild, a room less than backup_within
        # under its band, radiators and units both taking part, heats
        # with its radiators, the units the strategy has heat a comfort
        # gap behind. A room whose radiators alone led last (Room#led)
        # keeps them leading until the outside falls backup_kept under
        # backup_above, so an outside hovering there does not swap the lead
        # at every plan.
        class PumpBackup
            # parts: [[role, device], ...], the room's devices taking part
            # (Roles).
            def initialize(room, parts, settings)
                @room  = room
                @parts = parts
                @pump  = settings.pump
                @gap   = settings.comfort
            end

            # planned ({ device label => offset or nil }) with the
            # radiators leading when the lead holds; else as it is.
            def apply(planned) = holds? ? led(planned) : planned

            # The lead said, for why, in the words of the settings as the
            # house names them: "pump backup (10.2 °C ≥ 10.0)", "pump
            # backup kept (9.7 °C ≥ 9.5)" within the deadband; nil when it
            # does not hold.
            def note
                return unless holds?
                outside = @room.outside
                bound = @pump.backup_above
                kept = outside < bound
                bound = @pump.backup_bound(leading: true) if kept
                format("pump backup%<kept>s (%<outside>.1f °C ≥ %<bound>.1f)",
                       kept: (" kept" if kept), outside:, bound:)
            end

            # Mild, the room less than backup_within under its band, radiators
            # and units both taking part.
            def holds?
                return false unless @pump.backup?(@room.outside,
                                                  leading: leading?)
                return false unless @parts.map(&:first).uniq.size == 2
                now = @room.temperature or return false
                now > @room.band.heat - @pump.backup_within
            end

            private

            # Its radiators alone led it last (Room#led).
            def leading?
                led = @room.led or return false
                @parts.select { led.include?(it.last.label) }
                      .map(&:first).uniq == [:radiator]
            end

            # The radiators lead, the units the strategy has heat a gap
            # behind; one it rests stays so.
            def led(planned)
                @parts.to_h do |role, device|
                    next [device.label, 0.0] if role == :radiator
                    [device.label, planned[device.label] && -@gap]
                end
            end
        end
    end
end
