# frozen_string_literal: true

module Thermidor
    module Planner
        # How the strategies apply in the house: comfort's gap, how far
        # below the heat side its other sources come in (°C).
        StrategySettings = Data.define(:comfort) do
            def initialize(comfort: 0.5) = super
        end

        # What a strategy asks of a room's radiators and air conditioning,
        # as offsets from the band's heat side (nil: that device does not
        # heat); cooling is always the air conditioning's, at the band's
        # cool side.
        module Strategy
            # What each strategy is for, whatever the devices.
            ABOUT = {
                comfort: "the gentlest source by propagation leads; the " \
                         "others join once the room is a gap behind",
                quick: "every source able to heat, at once",
                quiet: "only the quiet sources",
                cheapest: "the cheapest source alone (for now, a heat " \
                          "pump: heats and cools on electricity)"
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

            # What `name` does with device classes of these capabilities
            # ({ :radiator or :aircon => caps }), in a room holding a
            # device of each: [[class, offset from the band's heat side],
            # ...], the lead first; the others take no part.
            def uses(name, settings, caps)
                devices = caps.transform_values do |each|
                    [Struct.new(:caps, :range).new(each, nil)]
                end
                room = Room.new(zone: nil, band: nil, strategy: name,
                                radiators: devices.fetch(:radiator, []),
                                aircons: devices.fetch(:aircon, []))
                Roles.new(room, 20.0).offsets(name, settings).compact
                     .sort_by { -it.last }
            end

            # { radiator:, aircon: } heat targets of a room, nil for a
            # class that does not heat: the strategy's rule over the
            # capabilities of the classes able to heat the room (Roles).
            def heat(room, settings = StrategySettings.new)
                heat = room.band&.heat or return { radiator: nil, aircon: nil }
                offsets = Roles.new(room, heat, room.excluded, room.effects)
                               .offsets(room.strategy.to_sym, settings)
                %i[radiator aircon].to_h do |role|
                    [role, offsets[role]&.then { (heat + it).round(1) }]
                end
            end
        end
    end
end
