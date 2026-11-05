# frozen_string_literal: true

module Thermidor
    module Planner
        # What the devices held on by hand (room.held) do to Plan: the
        # room's other devices kept a deadband away from what they work to,
        # so a radiator and an aircon never fight, and a held device working
        # past the room's band said, though left alone.
        module HeldDevices
            # By what a held device works to: what it does, the band's side
            # it must not pass, said how, compared how.
            PAST = { heat: ["heating", :cool, "above the band's cool side", :>],
                     cool: ["cooling", :heat, "below the band's heat side",
                            :<] }.freeze

            private

            # No cooling below a valve held heating, no heating above a unit
            # held cooling.
            def apart_from_held(room, target, direction)
                gap = Thermidor::Schedule::DEADBAND
                if direction == :cool
                    heating = held_most(room, :heat) or return target
                    [target, heating + gap].max
                else
                    cooling = held_most(room, :cool) or return target
                    [target, cooling - gap].min
                end
            end

            # The highest °C a held device heats to, or the lowest it cools
            # to; nil when none does.
            def held_most(room, direction)
                values = room.held.filter_map do |device|
                    works, value = held_work(room, device)
                    value if works == direction
                end
                direction == :heat ? values.max : values.min
            end

            def against_band(room)
                band = room.band or return
                room.held.each do |device|
                    line = past_band(room, device, band) or next
                    notice("#{room.zone}: #{device.label} left on, #{line}",
                           kind: :past_band, zone: room.zone,
                           device: device.label)
                end
            end

            def past_band(room, device, band)
                works, value = held_work(room, device)
                doing, side, limit, past = PAST.fetch(works) { return }
                bound = band.public_send(side) or return
                return unless value.public_send(past, bound)
                format("#{doing} to %.1f °C, #{limit} %.1f °C", value, bound)
            end

            # [:heat or :cool, °C in room terms] of a device left on; nil
            # when off. A held device's value is its own sensor's, not
            # written by the planner: brought back by the translation's
            # own gap for it, so it compares like
            # the band's and the other devices' targets, not past the
            # device's learned offset.
            def held_work(room, device)
                if device.is_a?(Radiator)
                    return unless device.mode == :heat && device.target
                    [:heat, in_room_terms(room, device, device.target)]
                elsif device.on && device.setpoint
                    direction = Plan.direction_of(device.mode) or return
                    [direction,
                     in_room_terms(room, device, device.setpoint,
                                   direction)]
                end
            end

            # value, a device's own-sensor reading, less the gap
            # the translation would add to a room-terms target to get it;
            # value unchanged where nothing can be translated.
            def in_room_terms(room, device, value, mode = nil)
                gap = @translation.target(room, device, value, mode).gap
                gap ? value - gap : value
            end
        end
    end
end
