# frozen_string_literal: true

module Thermidor
    module Planner
        # Plan's actions for one device: a unit's power and setpoint, a
        # radiator's mode and target, each on the device's step and
        # translated for its own sensor.
        module DevicePlan
            private

            # One that could not be read is left as it is, as a radiator
            # is (#radiator): what it holds now is not known, so nil must
            # not be read as off. Heating, one that may not heat itself is
            # off (#own).
            def aircon(room, device, target, direction)
                target = own(room, device, target) if direction == :heat
                label = device.label
                return unread(room, label) if device.mode.nil?
                return change(room, label, :power, true, false) if
                    target.nil? && device.on
                return if target.nil?
                change(room, label, :power, false, true) unless device.on
                aircon_setpoint(room, device, target, direction)
            end

            # direction: the mode the unit regulates in, its source's. A
            # unit reports the setpoint of the mode it is in: switching
            # mode, the one it will hold is not known, so it is written.
            def aircon_setpoint(room, device, target, direction)
                target = apart_from_held(room, target, direction)
                found = @translation.target(room, :aircon, target, direction)
                range = device.range_in(direction)
                now = (device.setpoint if
                    Plan.direction_of(device.mode) == direction)
                return if Fit.kept?(now, found.celsius, device.step, range)
                wanted = Fit.fit(found.celsius, device.step, range)
                retarget(room, device.label, :setpoint, now,
                         found.with(celsius: wanted))
            end

            # The class's target; a radiator that may not heat (on an
            # energy excluded now) goes to its least however it is listed.
            def radiators(room)
                target = Strategy.heat(room, @settings)[:radiator]
                room.radiators.each do |device|
                    radiator(room, device, own(room, device, target))
                end
            end

            # target, or nil for a device of the class that may not heat
            # itself; one whose caps are not given takes the class's.
            def own(room, device, target)
                return target unless target && device.caps
                target if Roles.heats?(device, room.excluded)
            end

            # Not heating is the least target, not off: a thermostat
            # switched off may be switched on again by its own driver,
            # while a least target holds. A radiator off already stays so.
            # One that could not be read is left as it is: what it holds
            # now is not known.
            def radiator(room, device, target)
                label = device.label
                return unread(room, label) if device.mode.nil?
                return radiator_least(room, device, label) unless target
                change(room, label, :mode, device.mode, :heat) unless
                    device.mode == :heat
                radiator_target(room, device, label, target)
            end

            # Its range's least, else its own; with neither, said.
            def radiator_least(room, device, label)
                return if device.mode == :off
                least = device.range&.min || device.least or
                    return no_least(room, label)
                return if device.target && (device.target - least).abs < 0.05
                change(room, label, :target, device.target, least)
            end

            def radiator_target(room, device, label, target)
                target = apart_from_held(room, target, :heat)
                found = @translation.target(room, :radiator, target)
                return if Fit.kept?(device.target, found.celsius, device.step,
                                    device.range)
                wanted = Fit.fit(found.celsius, device.step, device.range)
                retarget(room, label, :target, device.target,
                         found.with(celsius: wanted))
            end

            def unread(room, label)
                @warnings << "#{room.zone}: #{label} not read: left as it is"
            end

            def no_least(room, label)
                @warnings << "#{room.zone}: #{label} has no least target: " \
                             "left as it is"
            end
        end
    end
end
