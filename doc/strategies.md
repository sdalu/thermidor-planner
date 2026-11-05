# Strategies

How a room's devices share its heating, for [the planner](README.md):
which of them heat, and how far below the band's heat side. A strategy
ranks the devices by their own [caps](rooms.md#caps), whatever order
they are listed in and whatever they are called. Cooling is not ranked:
it is always the units', at the band's cool side, those whose
`caps.cool` is not `false`.

| Strategy   | Heats with                                                                                  |
| :--------- | :------------------------------------------------------------------------------------------ |
| `comfort`  | the gentlest devices by propagation (equally gentle ones together), the others a gap behind |
| `quick`    | every device able to heat, at once                                                          |
| `quiet`    | the quiet devices only                                                                      |
| `cheapest` | the devices whose heat costs least ([costs](#cheapest-and-costs))                           |

Any other name is planned as `cheapest`. `Strategy::ABOUT` holds a
sentence on each of the four, for a caller to show.

## Which devices take part

A device takes part when it was read, can heat (`caps.heat` is `true`),
on an energy not excluded now (`room.excluded`), and as low as the
band's heat side: a unit by its heating range (`range_in(:heat)`),
whatever mode it is in. One that does not take part rests: a radiator
at its least target, a unit off.

A room whose devices taking part are all of one kind (the same caps)
has nothing to rank them against: they all heat at the band, whatever
the strategy.

## Comfort

Gentleness is the first of `caps.propagation`: `radiation` and
`conduction` first, then `convection`, then `forced`. The gentlest
devices heat at the band's heat side; the others a gap behind, the
settings' `comfort` (0.5 °C), so they join once the room has fallen
that far. The gap is comfort's one setting (`Strategy.settings`,
described in `Strategy::FIELDS`).

`Strategy.uses(name, settings, caps, costs: {})` says what a strategy
does with one device of each class of the given caps, the lead first,
as offsets from the band's heat side; a class it rests is left out.
With the [README's](../README.md) caps:

```ruby
caps = { radiator: gas_radiator, aircon: heat_pump }
settings = P::StrategySettings.new

P::Strategy.uses(:comfort, settings, caps)
# => [[:radiator, 0.0], [:aircon, -0.5]]
P::Strategy.uses(:quick, settings, caps)
# => [[:radiator, 0.0], [:aircon, 0.0]]
P::Strategy.uses(:quiet, settings, caps)
# => [[:radiator, 0.0]]
P::Strategy.uses(:cheapest, settings, caps)
# => [[:aircon, 0.0]]
```

The gas radiator gives its heat by convection first, the heat pump's
unit by forced air: under comfort the radiator leads.

## Cheapest and costs

`room.costs` gives what a kWh of heat costs from each device now, by
label, in any one unit. With a cost for every device taking part, the
cheapest heat, equal costs together. Without, a guess: the heat pumps'
units alone (those that heat and cool on electricity), and with none
the radiators (the units, with no radiator taking part).

`settings.cost_margin` (a fraction, nil for none) keeps a lead from
flapping between two devices whose costs are close: a device that led
last (`room.led`) keeps the lead alone while its cost is at most the
least cost and that fraction of it. A device costing the least does not
join it.

```ruby
valve = P::Radiator.new(ref: "VA1", label: "valve:VA1", caps: gas_radiator,
                        temperature: 19.0, mode: :heat, target: 17.0,
                        range: 5.0..25.0, step: 0.5)
unit  = P::Aircon.new(ref: "1", label: "unit:1", caps: heat_pump,
                      system: "system:1", source: "pump", master: true,
                      temperature: 19.0, on: false, mode: :heat,
                      setpoint: 22.0, range: 18.0..30.0, step: 0.5)
band  = S::Setpoint.new(heat: 20, cool: 26)
room  = P::Room.new(zone: "living", band:, strategy: :cheapest,
                    radiators: [valve], aircons: [unit],
                    costs: { "valve:VA1" => 0.10, "unit:1" => 0.09 })
margin = P::StrategySettings.new(cost_margin: 0.15)

P::Strategy.heat(room)
# => { "valve:VA1" => nil, "unit:1" => 20.0 }
P::Strategy.heat(room.with(led: ["valve:VA1"]), margin)
# => { "valve:VA1" => 20.0, "unit:1" => nil }
dearer = room.with(led: ["valve:VA1"],
                   costs: { "valve:VA1" => 0.12, "unit:1" => 0.09 })
P::Strategy.heat(dearer, margin)
# => { "valve:VA1" => nil, "unit:1" => 20.0 }
```

`Strategy.heat(room, settings)` gives each device's heat target by
label (nil: it does not heat), which is why labels are unique in a
room. 0.10 is within 15 % of 0.09, so the valve that led keeps the lead;
0.12 is not.

## Effects

`room.effects`, an `Effects`, is what the room's energy rules do now
besides excluding, each device by its own energy:

| Field       | What it does                                                                                             |
| :---------- | :------------------------------------------------------------------------------------------------------- |
| `preferred` | energies that lead; the others leading before go a gap behind                                            |
| `avoided`   | energies that back up, a gap behind (below)                                                              |
| `caps`      | `{ energy => °C }`: a device on it heats at least that far under the band's heat side                    |
| `raises`    | `{ energy => °C }`: a device on it heats that far over the band's heat side, even one the strategy rests |

When avoided energies leave no device leading, those not avoided that
are nearest the lead take it; with every one avoided, nothing changes.
A raise also lifts the room's need: the room needs heat up to the
raised side when one of its devices on that energy may heat (read, able
to, its energy not excluded). `Effects.none` changes nothing, and
`Effects.of(verdicts)` builds one from anything answering the four
fields.

```ruby
comfort = room.with(strategy: :comfort, costs: {})
effects = ->(**given) { P::Effects.none.with(**given) }

P::Strategy.heat(comfort)
# => { "valve:VA1" => 20.0, "unit:1" => 19.5 }
P::Strategy.heat(comfort.with(effects: effects.(preferred: ["electricity"])))
# => { "valve:VA1" => 19.5, "unit:1" => 20.0 }
P::Strategy.heat(comfort.with(effects: effects.(caps: { "gas" => 2.0 })))
# => { "valve:VA1" => 18.0, "unit:1" => 19.5 }
P::Strategy.heat(comfort.with(effects: effects.(raises: { "electricity" => 1.5 })))
# => { "valve:VA1" => 20.0, "unit:1" => 21.5 }
```

## Mild lead

`settings.pump.mild_lead` (°C, nil: off) and `lead_gap` (1.0 °C): with
`room.outside` at or above `mild_lead`, a room less than `lead_gap`
under its band's heat side heats with its radiators, whatever the
strategy, `cheapest` included. Its units that heat go a comfort gap
behind, and those the strategy rests stay resting; the effects still
apply after. It holds only in a room where radiators and units both
take part, and with its temperature known.

```ruby
lead = P::StrategySettings.new(pump: P::PumpSettings.new(mild_lead: 8.0))
mild = room.with(outside: 10.0, measured: 19.6)

P::Strategy.heat(mild, lead)
# => { "valve:VA1" => 20.0, "unit:1" => 19.5 }
P::Strategy.heat(mild.with(measured: 18.9), lead)
# => { "valve:VA1" => nil, "unit:1" => 20.0 }
```

At 19.6 °C the valve leads and the unit, which `cheapest` alone would
have made the lead, calls its heat pump only at its backup target, 19.5 °C. At
18.9 °C the room is more than a degree under: `cheapest` decides again.

## Devices without caps

A device whose `caps` is nil takes no part of its own: it follows the
best target of the devices of its class that do, and none when none of
them heats.
