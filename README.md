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
| `Radiator` | a thermostat on a radiator: heats only; mode `:off` or `:heat`, a target on its step and range, `least` the target standing for "not heating" when the range gives none; a range open at an end (`nil..25.0`) is no bound on that side |
| `Aircon` | an air-conditioning unit: on or off, a mode (`:heat`, `:cool`, `:aux`, `:fan`, `:dry`, `:auto`, `:stop`), a setpoint; `system` the label of the units sharing its mode (set through the `master`), `source` the heat pump its system runs on; `ranges` its setpoints by mode |
| `Room` | a zone's band (nil: nothing to hold, its devices left off) and strategy, its radiators and units; `measured` its temperature from a reference of its own (else its devices' average, held ones included), `location` where that reference is, `excluded` the energies that may not heat now, `effects` what its energy rules do besides, `costs` what a kWh of heat costs from each device now (by label, any one unit), `outside` the outside °C now (nil: unknown), `led` the labels of the devices that led it last (nil: unknown), `held` its devices switched outside the planner |

A device read with a nil `mode` is unread: it gets no action, no vote,
and takes no part. `caps` answers `heat`, `cool`, `quiet`,
`energy` and `propagation` (most of its heat first: `radiation`,
`conduction`, `convection`, `forced`).

## What it gives

`Plan.new(rooms, settings:, translation:, pumps:, aside:).run` returns a
`Result`: `actions`, each an `Action` (zone, device label, setting
`:mode`, `:power`, `:target` or `:setpoint`, from, to, offset, why), and
`warnings`, sentences about what it could not do: each a `Notice`
(below), the translation's `notes` after them as it gave them.

- `settings`: a `StrategySettings`, comfort's gap (0.5 °C), `pump`, a
  `PumpSettings` saying how a heat pump is run (below), and
  `cost_margin`, cheapest's margin (below; nil, none).
- `translation`: makes the band's side into what a device's own sensor
  reads when the room holds it; answers `target(room, device, setpoint,
  mode)` for each device with a `Target` (`celsius`, `gap`), and
  `notes`. `AsIs`, the default, sends the band's side as is.
- `pumps`: `{ source => PumpState }`, what the caller knows of each heat
  pump (below).
- `aside`: system labels left to themselves: their mode is not set, their
  units get no action, and their rooms do not vote through them.

Only what differs from the device's state is an action, and a target
within one step of what the device holds is left alone. A room that
needs heat and gets none from its devices is warned of with why: an
energy excluded now, no device heating as low as its band, or no
device able to heat.

A `Notice` is a `String`, the sentence, which also says what it is
about: `kind`, and `zone`, `device` (a device's or a system's label)
and `source` (a heat pump's name), each nil when it is not about one.

| `kind` | Said of | About |
| :----- | :------ | :---- |
| `:unread` | a device not read, left as it is | zone, device |
| `:no_least` | a radiator not to heat with no least target, left | zone, device |
| `:unheated` | a room needing heat that none of its devices heat, with why | zone |
| `:unserved` | a room needing what its heat pump does not give | zone, source |
| `:held_against` | a unit held by hand the other way from its heat pump | zone, device, source |
| `:left_in_auto` | a system left in auto, its heat pump with no direction | device, source |
| `:past_band` | a device held by hand working past the band | zone, device |
| `:kept` | a heat pump's units kept as they are for its least time | source |

## Strategies

| Strategy   | Heats with |
| :--------- | :--------- |
| `comfort`  | the gentlest devices by propagation (equally gentle ones together), the others a gap behind |
| `quick`    | every device able to heat, at once |
| `quiet`    | the quiet devices only |
| `cheapest` | the devices whose heat costs least, by the room's `costs` (equal costs together), the last lead (`room.led`) kept while it costs no more than the least by `cost_margin` (alone: a device costing the least does not join it); without a cost for every device, the heat pumps alone (heat and cool on electricity), else the radiators |

The strategies rank devices, each by its own capabilities, whatever
order they are listed in. Cooling is always the units', at the band's
cool side, those whose `caps.cool` is not false (one that cannot cool is
off while its pump cools). A device takes part when it was read, can heat, on an
energy not excluded now, as low as the band's heat side; one that does
not rests, a radiator at its least target, a unit off. A room's devices
all of one kind (the same caps) have nothing to be ranked against and
heat at the band whatever the strategy. A device whose `caps` is nil
follows the best of its class. `Strategy.heat(room, settings)` gives
each device's target by label, so labels are unique in a room;
`Strategy.uses(name, settings, caps, costs: {})` says what a strategy
does with one device of each class of given capabilities (`costs`, for
`cheapest`, by class too), the lead first.

`Effects` are what a room's energy rules do, each device by its own
energy: `preferred` energies lead, `avoided` ones back up (those nearest
the lead taking it when none is left), `caps` keep a device at most so
far under the band, `raises` lift it over it (the room needing heat up
to that, when a device on that energy may heat it: read, able to heat,
its energy not excluded now).

## Heat pumps

The units on one heat pump run one direction. It comes from the rooms
with a unit on it that is read and planned, needing heat only when one
of its units on that heat pump may heat it, and cool only when one of
them can cool it: on a conflict, rooms needing
heat that have radiators able to heat them step aside, whatever their
strategy, and their radiators heat them; then the most rooms win; with no
need either way, the direction stays. A room left needing the other way
is warned of, and one left needing heat has its radiators heat it as
they would a room with no unit, whatever its strategy gave them.

Each system's mode is read on a unit that was read, its master's first,
and set through its master to the heat pump's direction, whatever mode
it is in (fan, dry, auto, stop included). With no direction to give,
units in fan, dry or auto are left running rather than switched off,
since those modes run without the heat pump (`Plan::RUNNING`). A system
that must keep its own mode (one put in fan or dry by hand, say) is
given in `aside:`: its mode is then never set, and its units read are
held from the start of the plan, as devices switched by hand are: no
power nor setpoint, no part in the strategy, no vote, their readings
still the room's (one unread is still said). A room they leave needing
heat is heated by its other devices, its radiators included, and said
when none heats; one left only to units held is the caller's, as a
zone handed over. `Plan::ASIDE` names the
modes a system runs in without the heat pump, for a caller deciding
what to set aside. A heat pump is named by whatever its units' `source`
holds, said as text.

What the caller knows of each heat pump is a `PumpState` in `pumps:`:
`held`, a direction set outside the planner and held (`:heat`, `:cool`,
or nil for neither); `running`, whether its compressor runs now (nil:
taken as whether one of its units is on); `switched_ago`, the minutes
since it last started or stopped (nil: unknown).

### Changing direction

How a tie and a room just past its band count is the settings' `pump`:

| `PumpSettings` | A room asks for the other direction | A tie |
| :------------- | :---------------------------------- | :---- |
| `switch: :heat` (default) | as soon as it is past its band | heat wins |
| `switch: :hysteresis, margin: 0.5` | only once `margin` °C past its band | the direction it runs stays |

With hysteresis, a pump whose compressor is stopped (`running` false,
or else none of its units on) goes either way with no margin, whatever
mode its systems are left in, and a room inside the margin is still
warned of.

### Short cycles

A heat pump's one compressor runs while any unit on it calls, and one
whose least output exceeds a mild day's load starts and stops over and
over. Its units are planned as one against it (`PumpCycle`), by these
settings of `PumpSettings`, each off until set:

| Setting | What it does |
| :------ | :----------- |
| `mild: 8.0, mild_deadband: 1.0` | with `room.outside` at or above `mild` in every room on the pump that gives one (its units planned or not: one unread still says the weather), and the pump heating: stopped, it starts only once a room on it is `mild_deadband` °C under its unit's target, and then every unit whose room is under its target starts with it, one run for all; running, a unit whose room reaches its target goes off, and the last one stops the pump |
| `min_on: 15, min_off: 10, urgent: 1.0` | a pump that started less than `min_on` minutes ago (its `switched_ago`) has its units that are on left as they are, power and setpoint, unless a unit's energy is excluded now, it runs another direction, or its room is `urgent` °C past its band the warm way; one stopped less than `min_off` ago has none of its units switched on or given a new setpoint, its rooms needing heat heated by their radiators meanwhile, until a room `urgent` °C past its band the cold way starts it, which ends the rest for all. A unit held off or on is said in a warning |
| `mild_lead: 8.0, lead_gap: 1.0` | per room: with `room.outside` at or above `mild_lead`, a room less than `lead_gap` °C under its band heats with its radiators, whatever the strategy (`cheapest` included), its units that heat a comfort gap behind and those the strategy rests resting; the energy rules' effects still apply after. Such a unit calls the pump only at its backup target |

An unknown outside temperature, room temperature or `switched_ago`
leaves the plan as it would be without the setting.

## Held devices and drifts

A device in `room.held` is not planned, but the room's others keep a
deadband (`Thermidor::Schedule::DEADBAND`) from what it works to, and
one working past the band is warned of. `Drifts.of(rooms, last,
planner:)` finds each setting read other than what was last set (`last`:
`{ [label, setting] => row }`, a row answering `setting`, `from`, `to`,
`at`, `offset`); `Drifts.band(drift, band)` is the band that holds what
was set from outside, for the room: an empty band for a drift switched
off (`off?`), one from the value for a temperature the band can take
(`band?`), and nil for any other (switched on, set to auto, a setpoint
in fan or dry).

## Known shortfalls

- Two device classes, radiators and units: a third (floor heating, a
  stove) has no role in the strategies.
- `cheapest` without a cost for every device guesses: a heat pump is
  taken as the cheapest, and with none the radiators.
- A unit holding a heat and a cool setpoint at once is planned one mode
  at a time.
