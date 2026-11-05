# frozen_string_literal: true

module Thermidor
    module Planner
        # The radiators leading in mild weather (PumpSettings mild_lead),
        # for Roles: with the outside mild, a room less than lead_gap
        # under its band, radiators and units both taking part, heats
        # with its radiators, the units the strategy has heat a comfort
        # gap behind. A room whose radiators alone led last (Room#led)
        # keeps them leading until the outside falls lead_deadband under
        # mild_lead, so an outside hovering there does not swap the lead
        # at every plan.
        class MildLead
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

            # The lead said, for why, when it changes planned: "mild lead
            # (10.2 °C ≥ 10.0)", "mild lead kept (9.7 °C ≥ 9.5)" within the
            # deadband; nil otherwise.
            def note(planned)
                return unless holds? && led(planned) != planned
                outside = @room.outside
                bound = @pump.mild_lead
                kept = outside < bound
                bound = @pump.lead_bound(leading: true) if kept
                format("mild lead%<kept>s (%<outside>.1f °C ≥ %<bound>.1f)",
                       kept: (" kept" if kept), outside:, bound:)
            end

            # Mild, the room less than lead_gap under its band, radiators
            # and units both taking part.
            def holds?
                return false unless @pump.lead?(@room.outside,
                                                leading: leading?)
                return false unless @parts.map(&:first).uniq.size == 2
                now = @room.temperature or return false
                now > @room.band.heat - @pump.lead_gap
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
