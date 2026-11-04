# frozen_string_literal: true

module Thermidor
    module Planner
        # Which of a room's device classes heat it, and how far below the
        # band, by the strategy's rule over their capabilities (caps,
        # Planner): quick, all of them; quiet, the quiet
        # ones; comfort, the gentlest by how it gives its heat, the others
        # a gap behind; cheapest, a heat pump (heats and cools on
        # electricity) before the rest, until real costs are known. A class
        # that cannot heat, or not as low as the band (frost below what the
        # air conditioning takes), or running on an energy excluded now
        # takes no part; one alone heats at the band
        # whatever the strategy.
        class Roles
            # radiation and conduction first, forced air last.
            GENTLE = { "radiation" => 0, "conduction" => 0, "convection" => 1,
                       "forced" => 2 }.freeze

            # excluded: energies the devices may not heat on now; effects:
            # what the rules do besides (Effects).
            def initialize(room, heat, excluded = [], effects = Effects.none)
                @excluded = excluded
                @effects  = effects
                classes = { radiator: room.radiators, aircon: room.aircons }
                @classes = classes.filter_map do |role, devices|
                    able(role, devices, heat)
                end.to_h
            end

            # { role => offset from the band's heat side, or nil }: the
            # strategy's, as the rules' effects change them.
            def offsets(strategy, settings)
                energies = @classes.transform_values(&:energy)
                offsets = strategy_offsets(strategy, settings)
                @effects.apply(offsets, energies, settings.comfort)
            end

            def strategy_offsets(strategy, settings)
                return all if @classes.size < 2
                case strategy
                when :quick then all
                when :quiet then quiet
                when :comfort then first(gentlest, -settings.comfort)
                else first(cheapest, nil)
                end
            end

            private

            def all = @classes.transform_values { 0.0 }

            def quiet = @classes.transform_values { it.quiet ? 0.0 : nil }

            # [role, capabilities] of a class able to heat to `heat`: an
            # unread device (nil mode) takes no part in
            # deciding it, as if it were not there, so it cannot make the
            # class able alone.
            def able(role, devices, heat)
                read = devices.reject { unread?(it) }
                caps = read.first&.caps or return
                return unless caps.heat && !@excluded.include?(caps.energy)
                return if read.all? { too_warm?(it, heat) }
                [role, caps]
            end

            def unread?(device) = device.respond_to?(:mode) && device.mode.nil?

            # Whether a device cannot heat as low as heat.
            def too_warm?(device, heat)
                range = heating_range(device)
                range && heat < range.min
            end

            # A unit's heating range, whatever mode it is in now.
            def heating_range(device)
                return device.range_in(:heat) if device.respond_to?(:range_in)
                device.range
            end

            def first(role, others)
                @classes.to_h { |each, _| [each, each == role ? 0.0 : others] }
            end

            def gentlest
                @classes.min_by do |_, caps|
                    GENTLE.fetch(caps.propagation.first, GENTLE.size)
                end.first
            end

            def cheapest
                @classes.min_by do |_, caps|
                    caps.cool && caps.energy == "electricity" ? 0 : 1
                end.first
            end
        end
    end
end
