# frozen_string_literal: true

module Thermidor
    module Planner
        # How the strategies apply in the house: comfort's gap, how far
        # below the heat side its other sources come in (°C); pump, how a
        # heat pump changes direction (PumpSettings).
        # cost_margin: under cheapest, how much more (a fraction) the kWh
        # of heat of a device that led last (room.led) may cost than the
        # cheapest's and keep the lead; nil, none. aliases: { a house's
        # own strategy name => the rule it follows (Strategy::RULES) }.
        StrategySettings = Data.define(:comfort, :pump, :cost_margin,
                                       :aliases) do
            def initialize(comfort: 0.5, pump: PumpSettings.new,
                           cost_margin: nil, aliases: {})
                raise ArgumentError, "negative cost_margin #{cost_margin}" if
                    cost_margin&.negative?
                aliases = aliases.to_h { |name, rule| [name.to_sym, rule] }
                StrategySettings.check_aliases(aliases)
                super
            end

            # The rule name follows: its own, or its alias's; nil when
            # neither.
            def rule(name)
                return if name.nil?
                name = name.to_sym
                Strategy::RULES.include?(name) ? name : aliases[name]
            end
        end

        class StrategySettings
            def self.check_aliases(aliases)
                wrong = aliases.reject { |_, rule| Strategy::RULES.include?(rule) }
                return if wrong.empty?
                raise ArgumentError, "an alias follows one of " \
                                     "#{Strategy::RULES.join(", ")}: " \
                                     "#{wrong.keys.join(", ")} does not"
            end
        end

        # What a strategy asks of a room's radiators and air conditioning,
        # device by device, as targets from the band's heat side (nil: that
        # device does not heat); cooling is always the air conditioning's,
        # at the band's cool side.
        module Strategy
            # The rules the planner knows; a house's own names follow one
            # through StrategySettings#aliases, any other is planned as
            # FALLBACK.
            RULES    = %i[comfort quick quiet cheapest].freeze
            FALLBACK = :comfort

            # What each strategy is for, whatever the devices.
            ABOUT = {
                comfort: "the gentlest source by propagation leads; the " \
                         "others join once the room is a gap behind",
                quick: "every source able to heat, at once",
                quiet: "only the quiet sources",
                cheapest: "the cheapest source alone, by the costs " \
                          "given (equal costs together), else the heat " \
                          "pumps (heat and cool on electricity), else " \
                          "the radiators"
            }.freeze

            # What each strategy setting means, and its unit.
            FIELDS = {
                gap: { unit: "°C",
                       description: "how far the room falls below the band " \
                                    "before the backup joins in" }
            }.freeze

            module_function

            # A strategy's own settings: { gap: °C } for comfort, none for
            # the others.
            def settings(name, given)
                name == :comfort ? { gap: given.comfort } : {}
            end

            # What strategy `name` is for (ABOUT), through its alias; a
            # name with neither raises ArgumentError.
            def about(name, settings = StrategySettings.new)
                ABOUT.fetch(known(name, settings))
            end

            # The rule of name, or ArgumentError.
            def known(name, settings)
                settings.rule(name) or
                    raise ArgumentError, "unknown strategy #{name}"
            end

            # A device as uses stands it for its class.
            Sample = Struct.new(:label, :caps, :range, :mode)

            # What `name` does with device classes of these capabilities
            # ({ :radiator or :aircon => caps }), in a room holding a
            # device of each: [[class, offset from the band's heat side],
            # ...], the lead first; the others take no part. costs: what a
            # kWh of heat costs from each class ({ class => cost }), for
            # cheapest. A name with no rule (nor alias) raises
            # ArgumentError.
            def uses(name, settings, caps, costs: {})
                rule = known(name, settings)
                Roles.new(sample(rule, caps, costs), 20.0)
                     .offsets(rule, settings).compact
                     .sort_by { -it.last }.map { [it.first.to_sym, it.last] }
            end

            # A room holding a device of each class, labelled by its
            # class, costs by those labels.
            def sample(name, caps, costs)
                devices = caps.to_h do |role, each|
                    [role, [Sample.new(role.to_s, each, nil, :heat)]]
                end
                Room.new(zone: nil, band: nil, strategy: name,
                         radiators: devices.fetch(:radiator, []),
                         aircons: devices.fetch(:aircon, []),
                         costs: costs.transform_keys(&:to_s))
            end

            # { device label => heat target, nil for none } over a room's
            # radiators and units: the strategy's rule over each device's
            # capabilities (Roles); all nil without a band.
            def heat(room, settings = StrategySettings.new)
                heat = room.band&.heat
                offsets = heat ? offsets(room, heat, settings) : {}
                (room.radiators + room.aircons).to_h do |device|
                    offset = offsets[device.label]
                    [device.label, offset && (heat + offset).round(1)]
                end
            end

            def offsets(room, heat, settings)
                roles(room, heat).offsets(room.strategy.to_sym, settings)
            end

            # What overrode the room's strategy, for an action's why: the
            # mild lead when it changed the lead (Roles#lead_note); none
            # without a band.
            def notes(room, settings = StrategySettings.new)
                heat = room.band&.heat or return []
                name = room.strategy or return []
                [roles(room, heat).lead_note(name.to_sym, settings)]
                    .compact
            end

            def roles(room, heat)
                Roles.new(room, heat, room.excluded, room.effects)
            end
        end
    end
end
