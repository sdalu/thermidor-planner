# frozen_string_literal: true

module Thermidor
    module Planner
        # A device setting found other than what the plan last set it to:
        # a hand at the thermostat, an app, the device's own driver.
        # applied and now as text, as kept and as the device reads them;
        # offset: the gap the plan had added for the device's own sensor;
        # mode: the unit's, which says whether a setpoint heats or cools.
        # A system's mode (device: the system's label) has no zone, and
        # its heat pump as source. planner: who set it last, as said.
        Drift = Data.define(:zone, :device, :setting, :applied, :now, :at,
                            :offset, :mode, :source, :planner) do
            def initialize(source: nil, planner: "the plan", **) = super

            def system? = zone.nil?

            # Switched off from outside: a radiator set off, a unit
            # powered off.
            def off? = !system? && %w[off false].include?(now)

            # Switched on: a radiator set to heat, a unit powered on.
            def on? = !system? && %w[heat true].include?(now)

            # Handed back to the device's own schedule: set to auto.
            def own? = !system? && setting == :mode && now == "auto"

            def temperature? = %i[target setpoint].include?(setting)

            # A temperature the band can take: a radiator's, or a unit's
            # while it heats or cools (not in fan, dry, auto or stop).
            def band? = temperature? && [nil, :heat, :cool, :aux].include?(mode)

            def to_s
                "#{zone || source}: #{device} #{setting} set to " \
                    "#{shown(now)} outside #{planner} (#{shown(applied)} at " \
                    "#{at.strftime("%H:%M")})"
            end

            private

            def shown(value)
                number = Float(value, exception: false)
                return format("%.1f °C", number) if number
                { "true" => "on", "false" => "off" }.fetch(value, value)
            end
        end

        # Drifts in the rooms' devices, against what was last set: any
        # value that differs. The plan writes a temperature on the
        # device's own step, which the device holds as written, so a
        # temperature read back otherwise was changed outside. A device
        # never set, or unread, has none. And the band that holds what was
        # set from outside, for the room as its reference sees it.
        module Drifts
            Schedule = Thermidor::Schedule

            # Two temperatures that are one, float noise aside.
            SAME = 0.05

            module_function

            # last: { [device label, setting name] => what was last set },
            # each answering setting, from, to (text), at and offset;
            # planner: who set it, as the drifts say. A system's mode
            # changed outside makes its units' setpoints read otherwise (a
            # two-setpoint unit reports the mode's): those are not drifts
            # of their own.
            def of(rooms, last, planner: "the plan")
                modes = modes(rooms, last)
                flipped = modes.map(&:device)
                found = modes + rooms.flat_map do |room|
                    planned(room, last, flipped) +
                        room.held.filter_map { switched(room, it, last) }
                end
                found.map { it.with(planner:) }
            end

            def planned(room, last, flipped)
                (room.radiators + room.aircons).flat_map do |device|
                    next radiator(room, device, last) if
                        device.is_a?(Radiator)
                    aircon(room, device, last, flipped.include?(device.system))
                end
            end

            # A device left to itself: only switching it counts, not what
            # its own driver then sets.
            def switched(room, device, last)
                return state(room, device.label, :mode, device.mode, last) if
                    device.is_a?(Radiator)
                state(room, device.label, :power, device.on, last)
            end

            # Each system's mode, read on any of its units (its master's
            # when there): every unit reports it.
            def modes(rooms, last)
                rooms.flat_map(&:devices).grep(Aircon)
                     .sort_by { it.master ? 0 : 1 }.uniq(&:system)
                     .filter_map { mode(it, last) }
            end

            def mode(master, last)
                row = last[[master.system, "mode"]]
                return unless row && master.mode && row.to != master.mode.to_s
                Drift.new(zone: nil, device: master.system, setting: :mode,
                          applied: row.to, now: master.mode.to_s, at: row.at,
                          offset: nil, mode: master.mode, source: master.source)
            end

            def radiator(room, device, last)
                label = device.label
                [state(room, label, :mode, device.mode, last),
                 temperature(room, label, :target, device, last)].compact
            end

            # A unit's setpoint is the one of the mode it is in: one written
            # before its system's mode last changed (outside, or by the
            # plan) is of the other mode, and not compared. Nor is an off
            # unit's: set while off, it leaves the unit off (so units
            # tried do), no hand on the room.
            def aircon(room, device, last, flipped)
                power = state(room, device.label, :power, device.on, last)
                return [power].compact if flipped || device.on == false ||
                                          other_mode?(device, last)
                [power, temperature(room, device.label, :setpoint, device,
                                    last)].compact
            end

            # A mode row only seen (from nil) is a baseline, no change.
            def other_mode?(device, last)
                set = last[[device.label, "setpoint"]] or return false
                mode = last[[device.system, "mode"]] or return false
                set.at < mode.at && mode.from && mode.from != mode.to
            end

            def state(room, label, setting, value, last)
                row = last[[label, setting.to_s]]
                return unless row && !value.nil? && row.to != value.to_s
                Drift.new(**known(room, label, row), now: value.to_s, mode: nil)
            end

            def temperature(room, label, setting, device, last)
                row = last[[label, setting.to_s]]
                value = setting == :target ? device.target : device.setpoint
                return unless row && value
                return if (Float(row.to) - value).abs < SAME
                mode = (device.mode if device.is_a?(Aircon))
                Drift.new(**known(room, label, row), now: value.to_s, mode:)
            end

            # What was last set of a device setting, as Drift takes it.
            def known(room, label, row)
                { zone: room.zone, device: label, setting: row.setting.to_sym,
                  applied: row.to, at: row.at, offset: row.offset }
            end

            # The band for drift's zone, from band (the zone's now): off
            # when switched off; else the side the device works on set to
            # its value less the offset the plan had added, the other side
            # kept at least DEADBAND away.
            def band(drift, band)
                return Schedule::Setpoint.new if drift.off?
                room = (Float(drift.now) - drift.offset.to_f).round(1)
                return cooled(room, band&.heat) if drift.mode == :cool
                heated(room, band&.cool)
            end

            def heated(room, cool)
                gap = Schedule::DEADBAND
                Schedule::Setpoint.new(heat: room,
                                       cool: cool && [cool, room + gap].max)
            end

            def cooled(room, heat)
                gap = Schedule::DEADBAND
                Schedule::Setpoint.new(heat: heat && [heat, room - gap].min,
                                       cool: room)
            end
        end
    end
end
