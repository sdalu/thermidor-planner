# frozen_string_literal: true

module Thermidor
    module Planner
        # How the strategies apply in the house: comfort's gap, how far
        # below the heat side its other sources come in (°C); pump, how a
        # heat pump changes direction (PumpSettings).
        StrategySettings = Data.define(:comfort, :pump) do
            def initialize(comfort: 0.5, pump: PumpSettings.new) = super
        end

        # What a strategy asks of a room's radiators and air conditioning,
        # device by device, as targets from the band's heat side (nil: that
        # device does not heat); cooling is always the air conditioning's,
        # at the band's cool side.
        module Strategy
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

            # A device as uses stands it for its class.
            Sample = Struct.new(:label, :caps, :range, :mode)

            # What `name` does with device classes of these capabilities
            # ({ :radiator or :aircon => caps }), in a room holding a
            # device of each: [[class, offset from the band's heat side],
            # ...], the lead first; the others take no part. costs: what a
            # kWh of heat costs from each class ({ class => cost }), for
            # cheapest.
            def uses(name, settings, caps, costs: {})
                Roles.new(sample(name, caps, costs), 20.0)
                     .offsets(name, settings).compact
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
                Roles.new(room, heat, room.excluded, room.effects)
                     .offsets(room.strategy.to_sym, settings)
            end
        end
    end
end
