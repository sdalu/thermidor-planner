# Held devices and drifts

A device switched outside [the planner](README.md), by a hand at the
thermostat, an app or its own driver, and held so, goes in
`room.held` (a `Radiator` or an `Aircon`). `Drifts` finds such hands:
each setting read other than what the plan last set.

## Held devices

A held device is not planned: it gets no action, takes no part in the
strategy and does not vote for its heat pump's direction. It is still
watched:

- its reading is still the room's, in the devices' average;
- the room's other devices keep a deadband
  (`Thermidor::Schedule::DEADBAND`) from what it works to: no unit
  cools below what a held device heats to plus the deadband, and no
  device heats above what a held device cools to less the deadband;
- one working past the band is said (`:past_band`,
  [warnings](warnings.md));
- a unit held on and running the other way from its heat pump is said
  (`:held_against`, [heat pumps](heat-pumps.md#systems-and-their-modes)).

What a held device works to is its own sensor's: it is brought back by
the gap the translation would add for it, so it compares with the band
as the room sees it. A radiator works to its target in `:heat`; a unit
on, to its setpoint in the direction of its mode; any other works to
nothing.

```ruby
band = S::Setpoint.new(heat: 20, cool: 26)
held = P::Radiator.new(ref: "VA", label: "valve:VA", caps: gas_radiator,
                       temperature: 27.0, mode: :heat, target: 26.5,
                       range: 5.0..25.0, step: 0.5)
unit = P::Aircon.new(ref: "1", label: "unit:1", caps: heat_pump,
                     system: "system:1", source: "pump", master: true,
                     temperature: 27.0, on: false, mode: :cool,
                     setpoint: 26.0, range: 18.0..30.0, step: 0.5)
room = P::Room.new(zone: "a", band:, strategy: :comfort, radiators: [],
                   aircons: [unit], held: [held])

result = P::Plan.new([room]).run
result.actions.map { [it.device, it.setting, it.to] }
# => [["unit:1", :power, true], ["unit:1", :setpoint, 27.5]]
result.warnings
# => ["a: valve:VA left on, heating to 26.5 °C, above the band's cool side 26.0 °C"]
```

The unit cools at 27.5 °C, a degree above the valve's 26.5 °C, rather
than at the band's 26 °C.

## Drifts

```ruby
Drifts.of(rooms, last, planner: "the plan")   # => [Drift, ...]
Drifts.band(drift, band)                      # => a Setpoint, or nil
```

`last` is `{ [label, setting] => row }`, what was last set of each
device setting, the setting's name as a `String` (`"target"`, `"power"`,
a system's `"mode"`); a row answers `setting`, `from`, `to` (text), `at`
(a `Time`) and `offset`. `Drifts.of` gives a `Drift` for each setting
read other than the row's `to`:

- a radiator's mode and target, a unit's power and setpoint, a
  system's mode (read on one of its units that was read, its master's
  first; its `zone` nil);
- a held device's switching only (a radiator's mode, a unit's power),
  not what its own driver then sets;
- a temperature as one when within 0.05 °C;
- not a setting never set, nor one read as nil;
- not a unit's setpoint when its system's mode was changed, outside or
  by the plan, after the setpoint was set, nor while the unit is off.

| `Drift`   | What it says                                                                    |
| :-------- | :------------------------------------------------------------------------------ |
| `off?`    | switched off: a radiator set off, a unit powered off                            |
| `on?`     | switched on: a radiator set to heat, a unit powered on                          |
| `own?`    | handed to the device's own schedule: its mode set to auto                       |
| `band?`   | a temperature the band can take: a radiator's, or a unit's in heat, cool or aux |
| `system?` | a system's mode                                                                 |
| `to_s`    | the sentence, `planner` naming who set it last                                  |

`Drifts.band(drift, band)` is the band holding what was set from
outside, for the room: an empty band (`off`) for a drift switched off;
for one the band can take, the side the device works on set to its
value less the offset the plan had added, the other side kept at least
the deadband away; nil for any other (switched on, set to auto, a
setpoint in fan or dry).

```ruby
Row = Data.define(:setting, :from, :to, :at, :offset)
at = Time.new(2026, 11, 5, 7, 30)
valve = held.with(temperature: 19.0, target: 22.0)
idle = unit.with(temperature: 19.0, mode: :heat, setpoint: 20.0)
living = P::Room.new(zone: "living", band:, strategy: :comfort,
                     radiators: [valve], aircons: [idle])
last = { ["valve:VA", "target"] => Row.new("target", "17.0", "20.0", at, 0.5),
         ["unit:1", "power"] => Row.new("power", "false", "true", at, nil) }

drifts = P::Drifts.of([living], last)
drifts.map(&:to_s)
# => ["living: valve:VA target set to 22.0 °C outside the plan (20.0 °C at 07:30)",
#     "living: unit:1 power set to off outside the plan (on at 07:30)"]
drifts.map { P::Drifts.band(it, band).to_s }  # => ["+21.5..+26.0", "off"]
```

The valve, set to 22.0 °C by hand, less the 0.5 °C offset the plan had
added for its own sensor, holds the room at 21.5 °C.
