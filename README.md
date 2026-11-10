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

## What it takes and gives

- `Room`s: each a zone's band and strategy, its `Radiator`s and
  `Aircon`s (units), and what holds now: its temperature, the energies
  excluded, the energy rules' `Effects`, the costs of its heat, the
  outside temperature, the devices switched by hand.
- `Plan.new(rooms, settings:, translation:, pumps:, aside:)`: a
  `StrategySettings` (comfort's gap, the cost margin, a `PumpSettings`
  for the heat pumps), a translation to each device's own sensor, a
  `PumpState` per heat pump, the systems left to themselves.
- The strategies: `comfort`, `quick`, `quiet`, `cheapest`.
- `#run` gives a `Result`: `actions`, each an `Action` (a device's
  mode, power, target or setpoint, from what it is to what it should
  be, and why), `warnings`, each a `Notice`, `waited`, whether
  each heat pump waits, for the next plan's `PumpState`, and
  `targets` and `overrides`, each radiator's room-scale target and
  what overrode its strategy, for a caller saying why.
- `Drifts`: the settings changed outside the plan, and the band that
  holds what was set.
- `EarlyStart`: whether a room starts a change ahead of its time, so
  it is in the band at the change, from the minutes until it, the rates
  the caller learned and the costs ahead; the band and strategy to hold
  meanwhile.

## Known shortfalls

- Two device classes, radiators and units: a third (floor heating, a
  stove) has no role in the strategies.
- `cheapest` without a cost for every device guesses: a heat pump is
  taken as the cheapest, and with none the radiators.
- A unit holding a heat and a cool setpoint at once is planned one mode
  at a time.

## Documentation

| Page                                   | What it covers                                                       |
| :------------------------------------- | :------------------------------------------------------------------- |
| [doc/README.md](doc/README.md)         | a plan's run, its terms, what the caller keeps                       |
| [Rooms and devices](doc/rooms.md)      | what `Plan` takes and gives, caps, targets, translation, `PumpState` |
| [Strategies](doc/strategies.md)        | which device heats, costs and the cost margin, effects, pump backup  |
| [Heat pumps](doc/heat-pumps.md)        | a pump's direction, `switch` and `margin`, systems set aside         |
| [Short cycles](doc/short-cycles.md)    | the pump wait, the least times, urgent rooms                         |
| [Held devices and drifts](doc/held.md) | devices switched by hand, and settings changed outside the plan      |
| [Warnings](doc/warnings.md)            | each `Notice` kind and its sentence                                  |
| [Early start](doc/early-start.md)      | starting a change ahead of its time, its rates, costs and notes      |

Why it is shaped so: [DESIGN.md](DESIGN.md).
