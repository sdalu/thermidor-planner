# Heat pumps

The units on one heat pump run one direction, for [the
planner](README.md): heat, cool, or none. A heat pump is named by its
units' `source`, whatever it holds, said as text; a system is the units
sharing one mode, named by their `system` label. The plan gives each
heat pump its direction, sets each of its systems' modes to it, and
plans its units in that direction, as one ([short
cycles](short-cycles.md)).

## Its direction

The direction comes from the rooms with a unit of their own on the heat
pump that was read. A room needing heat counts only when its strategy
has one of its units on that heat pump heat; one needing cool only when
one of them, read, can cool.

1. On a conflict, rooms needing heat that have radiators able to heat
   them step aside, whatever their strategy. Their radiators heat them
   as they would a room with no unit.
2. Then the most rooms win. A tie goes by the settings' `switch`
   ([below](#changing-direction)).
3. With no need either way, the direction the systems run now stays:
   the first one read, a master's first, that heats or cools (`:aux`
   heats).

A room left needing the other way is said (`:unserved`,
[warnings](warnings.md)). One left needing heat has its radiators heat
it as they would a room with no unit, whatever its strategy gave them.

Three rooms on one heat pump whose system cools, each with a band of
`+20..+26`: the kitchen cold with a radiator, the office warm, the
bedroom cold with only its unit.

```ruby
band = S::Setpoint.new(heat: 20, cool: 26)
unit = lambda do |zone, temperature, master|
    P::Aircon.new(ref: zone, label: "unit:#{zone}", caps: heat_pump,
                  system: "system:1", source: "pump", master:,
                  temperature:, on: false, mode: :cool, setpoint: 22.0,
                  range: 18.0..30.0, step: 0.5)
end
valve = P::Radiator.new(ref: "VA1", label: "valve:VA1", caps: gas_radiator,
                        temperature: 18.0, mode: :heat, target: 18.0,
                        range: 5.0..25.0, step: 0.5)
room = lambda do |zone, temperature, master, radiators = []|
    P::Room.new(zone:, band:, strategy: :comfort, radiators:,
                aircons: [unit.(zone, temperature, master)])
end
kitchen = room.("kitchen", 18.0, true, [valve])
office  = room.("office", 27.0, false)
bedroom = room.("bedroom", 18.5, false)

two = P::Plan.new([kitchen, office]).run
two.actions.map { [it.device, it.setting, it.from, it.to] }
# => [["unit:office", :power, false, true],
#     ["unit:office", :setpoint, 22.0, 26.0],
#     ["valve:VA1", :target, 18.0, 20.0]]
two.warnings  # => []

three = P::Plan.new([kitchen, office, bedroom]).run
three.actions.map { [it.device, it.setting, it.from, it.to] }
# => [["system:1", :mode, :cool, :heat],
#     ["unit:kitchen", :power, false, true],
#     ["unit:kitchen", :setpoint, nil, 19.5],
#     ["unit:bedroom", :power, false, true],
#     ["unit:bedroom", :setpoint, nil, 20.0],
#     ["valve:VA1", :target, 18.0, 20.0]]
three.warnings  # => ["office: needs cool, but pump heat"]
```

With two rooms, the kitchen steps aside for its radiator and the office
cools. With three, the bedroom, which has no radiator, and the office
tie, one each, and heat wins the tie. The kitchen, stepped aside, is
not counted; its unit heats with the heat pump all the same, and its
radiator as in a room with no unit.

## Changing direction

How a tie and a room just past its band count is the settings'
`pump`, a `PumpSettings`:

| `PumpSettings`                     | A room asks for the other direction  | A tie                       |
| :--------------------------------- | :----------------------------------- | :-------------------------- |
| `switch: :heat` (default)          | as soon as it is past its band       | heat wins                   |
| `switch: :hysteresis, margin: 0.5` | only once more than `margin` °C past | the direction it runs stays |

With hysteresis, a heat pump whose compressor is stopped (its
`PumpState#running` false, or, unknown, none of its units on) goes
either way with no margin, whatever mode its systems are left in. A
room inside the margin is still said. `PumpSettings` refuses an unknown
`switch`, a nil `margin` and a negative one with `ArgumentError`.

```ruby
cooling = P::Room.new(zone: "a", band:, strategy: :comfort, radiators: [],
                      aircons: [unit.("a", 19.7, true).with(on: true)])
hysteresis = P::StrategySettings.new(
    pump: P::PumpSettings.new(switch: :hysteresis, margin: 0.5)
)
stopped = { "pump" => P::PumpState.new(running: false) }

P::Plan.new([cooling]).run.actions.map { [it.device, it.setting, it.to] }
# => [["system:1", :mode, :heat], ["unit:a", :setpoint, 20.0]]
held = P::Plan.new([cooling], settings: hysteresis).run
held.actions.map { [it.device, it.setting, it.to] }
# => [["unit:a", :power, false]]
held.warnings  # => ["a: needs heat, but pump cool"]
free = P::Plan.new([cooling], settings: hysteresis, pumps: stopped).run
free.actions.map { [it.device, it.setting, it.to] }
# => [["system:1", :mode, :heat], ["unit:a", :setpoint, 20.0]]
```

At 19.7 °C the room is 0.3 °C under its band: the switch turns the
heat pump at once; hysteresis keeps it cooling, the unit off and the
room said, until the room is more than 0.5 °C under, or the
compressor stops.

## A direction held

`PumpState#held` is a direction set outside the planner and held: it
wins over the rooms. `:heat` or `:cool` runs that way; nil keeps the
heat pump off. The rooms it does not serve are said, as for any
direction.

```ruby
off = P::Plan.new([cooling], pumps: { "pump" => P::PumpState.new(held: nil) })
off.run.warnings
# => ["a: needs heat, but pump stays off"]
```

## Systems and their modes

Each system's mode is read on one of its units that was read, its
master's first, and set to the heat pump's direction, whatever mode it
is in (`:fan`, `:dry`, `:auto`, `:stop` included). The action names the
system's label, for the caller to set through its master; a system in
`:aux` already heats. With no direction to give, units in
`:fan`, `:dry` or `:auto` (`Plan::RUNNING`) are left running, since
those modes run without the heat pump, and a system left in `:auto` is
said (`:left_in_auto`).

A unit held by hand on the heat pump (in `room.held`), on and running
the other way from the direction the rooms gave, is said
(`:held_against`): its own room did not vote, so it would otherwise
lose its hand unsaid. Its system's mode is set like any other's.

## Systems set aside

A system that must keep its own mode (one put in fan or dry by hand,
say) is given in `aside:`. Its mode is then never set, and its units
that were read are held from the start of the plan, as [devices
switched by hand](held.md) are: no power nor setpoint, no part in the
strategy, no vote, their readings still the room's. One unread is
still said. A room they leave needing heat is heated by its other
devices, its radiators included, and said when none heats; one left
only to units held is the caller's, as a zone handed over.
`Plan::ASIDE` (`:fan`, `:dry`) names the modes a system runs in without
the heat pump, for a caller deciding what to set aside.

```ruby
dry = unit.("b", 19.0, true).with(system: "system:2", on: true, mode: :dry)
radiator = valve.with(label: "valve:VB", temperature: 19.0, target: 17.0)
aside = P::Room.new(zone: "b", band:, strategy: :comfort,
                    radiators: [radiator], aircons: [dry])

left = P::Plan.new([aside], aside: ["system:2"]).run
left.actions.map { [it.device, it.setting, it.to] }
# => [["valve:VB", :target, 20.0]]
```
