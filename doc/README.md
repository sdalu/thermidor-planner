# The planner and its parts

thermidor-planner works out, for every room of a house at one moment,
what to tell its devices so the room holds the band the schedule
decided: which way each heat pump runs, which devices heat, and the
target each one should hold. It decides only. Reading the devices,
the energy rules and writing the actions are the caller's.

- [Concepts](#concepts)
- [A run](#a-run)
- [The parts](#the-parts)
- [What the caller keeps](#what-the-caller-keeps)

## Concepts

| Term        | Class              | Meaning                                                                |
| :---------- | :----------------- | :--------------------------------------------------------------------- |
| room        | `Room`             | a zone's band and strategy, its devices, what is known now             |
| radiator    | `Radiator`         | a thermostat on a radiator: heats only                                 |
| unit        | `Aircon`           | an air-conditioning unit, on a system, on a heat pump                  |
| system      | a label (`String`) | the units sharing one mode, set through their master                   |
| heat pump   | a name (`source`)  | what a system runs on; one direction for every unit on it              |
| caps        | anything (duck)    | what a device can do: `heat`, `cool`, `quiet`, `energy`, `propagation` |
| strategy    | a Symbol           | which devices heat, and how far below the band                         |
| settings    | `StrategySettings` | comfort's gap, the cost margin, how a heat pump is run                 |
| pump state  | `PumpState`        | what the caller knows of a heat pump now                               |
| translation | anything (duck)    | a band's side made into what a device's own sensor reads               |
| action      | `Action`           | one setting of one device, from what it is to what it should be        |
| warning     | `Notice`           | a sentence about what the plan could not do, and what about            |

The band (`Thermidor::Schedule::Setpoint`) and the strategy come from
thermidor-schedule's decision for the zone.

## A run

```ruby
result = Thermidor::Planner::Plan.new(rooms, settings:, translation:,
                                      pumps:, aside:).run
result.actions   # [Action, ...]
result.warnings  # [Notice, ...], then the translation's notes
```

`Plan#run` goes over the heat pumps first, then the rooms:

1. Each heat pump, named by its units' `source`: its direction from the
   rooms with a unit on it ([heat pumps](heat-pumps.md)); each of its
   systems' modes set to it through the master; its units planned as
   one, against short cycles ([short cycles](short-cycles.md)); the
   rooms it leaves needing heat handed to their radiators.
2. Each room: its radiators to their targets, by the strategy
   ([strategies](strategies.md)); a room needing heat that none of its
   devices heat, said; a device held by hand working past the band,
   said ([held devices](held.md)).

The actions come in that order: each heat pump's systems' modes, then
its units, then each room's radiators. Only what differs from what a
device reads is an action.

## The parts

| Page                            | What it covers                                                       |
| :------------------------------ | :------------------------------------------------------------------- |
| [Rooms and devices](rooms.md)   | what `Plan` takes and gives, caps, targets, translation, `PumpState` |
| [Strategies](strategies.md)     | which device heats, costs and the cost margin, effects, mild lead    |
| [Heat pumps](heat-pumps.md)     | a pump's direction, `switch` and `margin`, systems set aside         |
| [Short cycles](short-cycles.md) | `PumpCycle`: the mild gap, the least times, urgent rooms             |
| [Held devices](held.md)         | devices switched by hand, and drifts from what was set               |
| [Warnings](warnings.md)         | each `Notice` kind and its sentence                                  |

## What the caller keeps

The planner reads no device, no store and no clock. That leaves the
caller to:

- read each device into a `Radiator` or an `Aircon` (an unread one with
  a nil `mode`), and give each its `caps`;
- build each room from the schedule's decision: its band and strategy;
- say what holds now: the energies excluded, the energy rules'
  `Effects`, the costs of a kWh of heat, the outside temperature, the
  devices that led last, the devices switched by hand;
- tell what it knows of each heat pump (`PumpState`), and which systems
  to leave to themselves (`aside:`);
- write the actions, and keep what it wrote, for `Drifts` to compare
  with what the devices read next.
