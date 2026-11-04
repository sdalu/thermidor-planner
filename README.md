# thermidor-planner

What to tell a house's heating and air conditioning so each room holds
the comfort band its schedule decided: which devices heat, which way
each heat pump runs, and the target each device should hold.

It decides only: reading the devices and writing to them is the
caller's. The bands and strategies come from `thermidor-schedule`, the
gem of the same family; ClimatControl reads tado thermostats and
Airzone units, plans with this gem and writes the actions back.

Ruby ≥ 3.4; depends on `thermidor-schedule` alone.

```ruby
# Gemfile
gem "thermidor-planner", github: "sdalu/thermidor-planner"
```

## A room, its devices, a plan

```ruby
require "thermidor/planner"

P = Thermidor::Planner
S = Thermidor::Schedule

# What a device can do, read by duck typing.
Caps = Data.define(:heat, :cool, :quiet, :energy, :propagation)
gas_radiator = Caps.new(heat: true, cool: false, quiet: true,
                        energy: "gas", propagation: %w[convection radiation])
heat_pump    = Caps.new(heat: true, cool: true, quiet: false,
                        energy: "electricity", propagation: %w[forced])

valve = P::Radiator.new(ref: "VA1", label: "valve:VA1", caps: gas_radiator,
                        temperature: 18.4, mode: :off, target: 17.0,
                        range: 5.0..25.0, step: 0.5)
unit  = P::Aircon.new(ref: "1", label: "unit:living", caps: heat_pump,
                      system: "system:1", source: "pump", master: true,
                      temperature: 18.6, on: false, mode: :cool,
                      setpoint: 24.0, range: 18.0..30.0, step: 0.5)
living = P::Room.new(zone: "living", band: S::Setpoint.new(heat: 20, cool: 26),
                     strategy: :comfort, radiators: [valve], aircons: [unit])

result = P::Plan.new([living]).run
result.actions.map { [it.device, it.setting, it.from, it.to] }
# => [["system:1", :mode, :cool, :heat],
#     ["unit:living", :power, false, true],
#     ["unit:living", :setpoint, nil, 19.5],
#     ["valve:VA1", :mode, :off, :heat],
#     ["valve:VA1", :target, 17.0, 20.0]]
result.actions.first.why  # => "source pump"
result.actions.last.why   # => "comfort, +20.0..+26.0, at 18.5 (devices)"
result.warnings           # => []
```

Under comfort the valve, the gentlest, heats at the band's heat side and
the unit a gap (0.5 °C) behind; the heat pump turns from cool to heat for
it, and the unit's setpoint is written for the mode it will run in.

## What it takes

| Type | What it is |
| :--- | :--------- |
| `Radiator` | a thermostat on a radiator: heats only; mode `:off` or `:heat`, a target on its step and range, `least` the target standing for "not heating" when the range gives none |
| `Aircon` | an air-conditioning unit: on or off, a mode (`:heat`, `:cool`, `:aux`, `:fan`, `:dry`, `:auto`, `:stop`), a setpoint; `system` the label of the units sharing its mode (set through the `master`), `source` the heat pump its system runs on; `ranges` its setpoints by mode |
| `Room` | a zone's band (nil: nothing to hold, its devices left off) and strategy, its radiators and units; `measured` its temperature from a reference of its own (else its devices' average), `location` where that reference is, `excluded` the energies that may not heat now, `effects` what its energy rules do besides, `costs` what a kWh of heat costs from each device now (by label, any one unit), `held` its devices switched outside the planner |

A device read with a nil `mode` is unread: it gets no action, no vote,
and takes no part. `caps` answers `heat`, `cool`, `quiet`,
`energy` and `propagation` (most of its heat first: `radiation`,
`conduction`, `convection`, `forced`).

## What it gives

`Plan.new(rooms, settings:, translation:, held:, aside:).run` returns a
`Result`: `actions`, each an `Action` (zone, device label, setting
`:mode`, `:power`, `:target` or `:setpoint`, from, to, offset, why), and
`warnings`, sentences about what it could not do.

- `settings`: a `StrategySettings`, comfort's gap (0.5 °C).
- `translation`: makes the band's side into what a device's own sensor
  reads when the room holds it; answers `target(room, device, setpoint,
  mode)` for each device with a `Target` (`celsius`, `gap`), and
  `notes`. `AsIs`, the default, sends the band's side as is.
- `held`: `{ source => :heat, :cool or nil }`, heat pumps' directions
  set outside and held.
- `aside`: system labels left to themselves, their mode not set.

Only what differs from the device's state is an action, and a target
within one step of what the device holds is left alone.

## Strategies

| Strategy   | Heats with |
| :--------- | :--------- |
| `comfort`  | the gentlest devices by propagation (equally gentle ones together), the others a gap behind |
| `quick`    | every device able to heat, at once |
| `quiet`    | the quiet devices only |
| `cheapest` | the devices whose heat costs least, by the room's `costs` (equal costs together); without a cost for every device, the heat pumps alone (heat and cool on electricity), else the radiators |

The strategies rank devices, each by its own capabilities, whatever
order they are listed in. Cooling is always the units', at the band's
cool side. A device takes part when it was read, can heat, on an
energy not excluded now, as low as the band's heat side; one that does
not rests, a radiator at its least target, a unit off. A room's devices
all of one kind (the same caps) have nothing to be ranked against and
heat at the band whatever the strategy. A device whose `caps` is nil
follows the best of its class. `Strategy.heat(room, settings)` gives
each device's target by label, so labels are unique in a room;
`Strategy.uses(name, settings, caps)` says what a strategy does with
one device of each class of given capabilities, the lead first.

`Effects` are what a room's energy rules do, each device by its own
energy: `preferred` energies lead, `avoided` ones back up (those nearest
the lead taking it when none is left), `caps` keep a device at most so
far under the band, `raises` lift it over it (the room needing heat up
to that).

## Heat pumps

The units on one heat pump run one direction. It comes from the rooms
with a unit on it that is read and planned, needing heat only when one
of its units on that heat pump may heat it: on a conflict, rooms needing
heat that have radiators step aside; then the most rooms win, heat on a
tie; with no need either way, the direction stays. A room left needing
the other way is warned of. Each system's mode is read on a unit that
was read, its master's first, and set through its master; a system in
fan or dry runs without the heat pump and is left running. A heat pump
is named by whatever its units' `source` holds, said as text.

## Held devices and drifts

A device in `room.held` is not planned, but the room's others keep a
deadband (`Thermidor::Schedule::DEADBAND`) from what it works to, and
one working past the band is warned of. `Drifts.of(rooms, last,
planner:)` finds each setting read other than what was last set (`last`:
`{ [label, setting] => row }`, a row answering `setting`, `from`, `to`,
`at`, `offset`); `Drifts.band(drift, band)` is the band that holds what
was set from outside, for the room.

## Known shortfalls

- Two device classes, radiators and units: a third (floor heating, a
  stove) has no role in the strategies.
- `cheapest` without a cost for every device guesses: a heat pump is
  taken as the cheapest, and with none the radiators.
- A unit holding a heat and a cool setpoint at once is planned one mode
  at a time.
