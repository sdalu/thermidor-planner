# frozen_string_literal: true

module Thermidor
    module Planner
        # Which of a room's devices heat it, and how far below the band, by
        # the strategy's rule over each device's capabilities (caps,
        # Planner): quick, all of them; quiet, the quiet ones; comfort, the
        # gentlest by how they give their heat (ties together), the others
        # a gap behind; cheapest, the devices whose heat costs least when
        # the room gives every one a cost (ties together), else the heat
        # pumps (heat and cool on electricity), else the radiators. A
        # device takes part when it was read, can heat, on an energy not
        # excluded now, as low as the band; devices all of one kind (the
        # same caps) have nothing to be ranked against and heat at the
        # band whatever the strategy. A device whose caps are not given
        # follows its class's best.
        class Roles
            # radiation and conduction first, forced air last.
            GENTLE = { "radiation" => 0, "conduction" => 0, "convection" => 1,
                       "forced" => 2 }.freeze

            # The device classes, in the order cheapest falls back on.
            ROLES = %i[radiator aircon].freeze

            # Whether a device may heat: it can, on an energy not excluded.
            def self.heats?(device, excluded)
                caps = device.caps or return false
                caps.heat == true && !excluded.include?(caps.energy)
            end

            # Whether a unit may cool: its caps do not say it cannot (one
            # without caps follows its class, which cools).
            def self.cools?(device) = device.caps&.cool != false

            # Whether a device takes part in heating to `heat`: read, it may
            # heat, and as low as that (a unit by its heating range,
            # whatever mode it is in now).
            def self.able?(device, excluded, heat)
                return false if device.respond_to?(:mode) && device.mode.nil?
                return false unless heats?(device, excluded)
                range = if device.respond_to?(:range_in)
                            device.range_in(:heat)
                        else
                            device.range
                        end
                least = range&.begin
                !(least && heat < least)
            end

            # excluded: energies the devices may not heat on now; effects:
            # what the rules do besides (Effects).
            def initialize(room, heat, excluded = [], effects = Effects.none)
                @excluded = excluded
                @effects  = effects
                @costs    = room.costs
                @room     = room
                classes = { radiator: room.radiators, aircon: room.aircons }
                read = classes.flat_map do |role, devices|
                    devices.reject { unread?(it) }.map { [role, it] }
                end
                @parts = read.select { |_, device| part?(device, heat) }
                @followers = read.reject { |_, device| device.caps }
            end

            # { device label => offset from the band's heat side, or nil }
            # for the devices taking part and those following their class:
            # the strategy's, the radiators leading in mild weather
            # (PumpBackup), as the rules' effects change them.
            def offsets(strategy, settings)
                planned = strategy_offsets(strategy, settings)
                found = effected(pump_backup(settings).apply(planned), settings)
                found.merge(following(found))
            end

            # The pump backup said, for why, when it changes what the
            # strategy and the effects ask (PumpBackup#note); nil otherwise.
            def backup_note(strategy, settings)
                planned = strategy_offsets(strategy, settings)
                lead = pump_backup(settings)
                return if effected(lead.apply(planned), settings) ==
                          effected(planned, settings)
                lead.note
            end

            # strategy: a rule, an alias of one (StrategySettings), or
            # else planned as Strategy::FALLBACK.
            def strategy_offsets(strategy, settings)
                return by { 0.0 } if @parts.map { it.last.caps }.uniq.size < 2
                case settings.rule(strategy) || Strategy::FALLBACK
                when :quick then by { 0.0 }
                when :quiet then by { it.caps.quiet ? 0.0 : nil }
                when :comfort then comfort(@room.gap_in(settings))
                else cheapest(settings.cost_margin)
                end
            end

            private

            def pump_backup(settings) = PumpBackup.new(@room, @parts, settings)

            def effected(planned, settings)
                energies = @parts.to_h { |_, one| [one.label, one.caps.energy] }
                @effects.apply(planned, energies, @room.gap_in(settings))
            end

            def by = @parts.to_h { |_, device| [device.label, yield(device)] }

            def part?(device, heat) = Roles.able?(device, @excluded, heat)

            def unread?(device) = device.respond_to?(:mode) && device.mode.nil?

            # The gentlest lead, together when equally gentle.
            def comfort(gap)
                least = @parts.map { gentle(it.last) }.min
                by { gentle(it) == least ? 0.0 : -gap }
            end

            def gentle(device)
                GENTLE.fetch(device.caps.propagation.first, GENTLE.size)
            end

            # The least costly, by the room's costs when every device has
            # one; else the heat pumps alone; with none, the first class
            # (ROLES) holding a device that takes part.
            def cheapest(margin)
                return costed(margin) if @parts.all? { @costs[it.last.label] }
                return by { pump?(it) ? 0.0 : nil } if
                    @parts.any? { pump?(it.last) }
                first_class
            end

            def first_class
                first = ROLES.find { |role| @parts.any? { it.first == role } }
                @parts.to_h do |role, device|
                    [device.label, role == first ? 0.0 : nil]
                end
            end

            # The least costly, together when equal; the last lead
            # (room.led) kept while it costs no more than the least by the
            # margin.
            def costed(margin)
                least = @parts.map { @costs[it.last.label] }.min
                kept = kept_lead(least, margin)
                return by { kept.include?(it.label) ? 0.0 : nil } if kept.any?
                by { @costs[it.label] == least ? 0.0 : nil }
            end

            def kept_lead(least, margin)
                return [] unless margin && @room.led
                bound = least + (least.abs * margin)
                @parts.map(&:last).select do |device|
                    @room.led.include?(device.label) &&
                        @costs[device.label] <= bound
                end.map(&:label)
            end

            def pump?(device)
                device.caps.cool == true && device.caps.energy == "electricity"
            end

            # A device without caps: its class's best offset, nil when none
            # of its class takes part.
            def following(found)
                @followers.to_h do |role, device|
                    offsets = @parts.select { it.first == role }
                                    .filter_map { found[it.last.label] }
                    [device.label, offsets.max]
                end
            end
        end
    end
end
