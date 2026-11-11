# Rooms and devices

What [the planner](README.md) takes, a `Room` for each zone holding its
devices, and what it gives back, a `Result`. Every one is a `Data`
value, built by the caller from what it read.

```ruby
Plan.new(rooms, settings: StrategySettings.new, translation: AsIs.new,
         pumps: {}, aside: []).run   # a Result
```

| Argument      | What it is                                                                                                                                        |
| :------------ | :------------------------------------------------------------------------------------------------------------------------------------------------ |
| `rooms`       | `Room`, ...                                                                                                                                       |
| `settings`    | a `StrategySettings`: `comfort` (0.5 °C), `pump` (a `PumpSettings`), `cost_margin` (nil), `aliases` (`{}`, a house's own strategy names => rules) |
| `translation` | answers `target` and `notes` ([below](#translation)); `AsIs` by default                                                                           |
| `pumps`       | `{ source => PumpState }`, what the caller knows of each heat pump                                                                                |
| `aside`       | the labels of systems left to themselves ([heat pumps](heat-pumps.md#systems-set-aside))                                                          |

`StrategySettings` refuses a negative `cost_margin` with
`ArgumentError`. `comfort` and `cost_margin` are the
[strategies'](strategies.md), `pump` the [heat pumps'](heat-pumps.md)
and [short cycles'](short-cycles.md).

## Devices

A device's `label` is its name in actions, warnings and drifts, unique
in its room. `ref` is the caller's own and not read by the planner. A
device read with a nil `mode` is unread: it gets no action, no vote and
takes no part, and is said ([warnings](warnings.md)).

| `Radiator` | What it is                                                                   |
| :--------- | :--------------------------------------------------------------------------- |
| `mode`     | `:off` or `:heat`; nil, unread                                               |
| `target`   | the °C it holds                                                              |
| `range`    | the targets it takes; nil, any; open at an end (`nil..25.0`), no bound there |
| `step`     | the targets it takes are on it                                               |
| `least`    | the target standing for "not heating" when `range` gives none (default nil)  |

| `Aircon`   | What it is                                                                                            |
| :--------- | :---------------------------------------------------------------------------------------------------- |
| `on`       | powered on or off                                                                                     |
| `mode`     | `:heat`, `:cool`, `:aux` (heat with a backup heater), `:fan`, `:dry`, `:auto`, `:stop`; nil, unread   |
| `setpoint` | the setpoint of the mode it is in                                                                     |
| `system`   | the label of the units sharing its mode                                                               |
| `master`   | whether the system's mode is set through it                                                           |
| `source`   | the heat pump its system runs on, named as the caller likes                                           |
| `range`    | its setpoints now, in the mode it is in                                                               |
| `ranges`   | its setpoints by mode (`{ heat: 16.0..30.0 }`), those it gives; `range` for the others (default `{}`) |
| `step`     | as a radiator's                                                                                       |

Both also take `caps` and `temperature`, what the device's own sensor
reads (nil: none).

### Caps

`caps` is read by duck typing: anything answering

| Method        | Answer                                                                                     |
| :------------ | :----------------------------------------------------------------------------------------- |
| `heat`        | whether it can heat (only `true` counts)                                                   |
| `cool`        | whether it can cool (a unit cools unless it says `false`)                                  |
| `quiet`       | whether it is quiet, for `quiet`                                                           |
| `energy`      | a name (`"gas"`, `"electricity"`), for exclusions and effects                              |
| `propagation` | how it gives its heat, most of it first: `radiation`, `conduction`, `convection`, `forced` |

A device whose `caps` is nil does not heat by itself: it follows the
best of its class ([strategies](strategies.md#devices-without-caps)).

## Rooms

`Room.new(zone:, band:, strategy:, radiators:, aircons:, **)`:

| Field      | What it is (default)                                                                |
| :--------- | :---------------------------------------------------------------------------------- |
| `band`     | the `Setpoint` to hold; nil, nothing to hold: no device gets a target               |
| `strategy` | a Symbol ([strategies](strategies.md)); nil is refused with `ArgumentError`         |
| `measured` | its °C from a reference of its own (nil)                                            |
| `location` | where that reference is, for a translation (nil)                                    |
| `excluded` | the energies its devices may not heat on now (`[]`)                                 |
| `effects`  | what its energy rules do besides (`Effects.none`; [effects](strategies.md#effects)) |
| `costs`    | what a kWh of heat costs from each device now, by label, any one unit (`{}`)        |
| `outside`  | the outside °C now (nil: unknown)                                                   |
| `led`      | the labels of the devices that led it last, at the band (nil: unknown)              |
| `gap`      | its own comfort gap (°C), over the house's `StrategySettings#comfort` (nil: the house's) |
| `held`     | its devices switched outside the planner (`[]`; [held devices](held.md))            |

`Room#temperature` is `measured`, else its devices' readings averaged
(held ones included, rounded to 0.1), else nil. `Room#need` is `:heat`
below the band's heat side (lifted by a raise, [effects](strategies.md#effects)),
`:cool` above its cool side, else nil; nil without a band or a
temperature.

## What it gives

`Result`: `actions`, `warnings`, and `waited`, `{ heat pump => whether
it waits }` ([pump wait](short-cycles.md#the-pump-wait)), which the
caller keeps and gives back as `PumpState#waited` at the next plan.
`targets`, `{ zone => { radiator label => target } }`, is what each
room's radiators were planned to on the room's scale: `Strategy.heat`'s
target after the pump wait lowered it, before the translation and the
device's step (nil: not heating). `overrides`, `{ zone => { device label
=> [sentence, ...] } }`, is what overrode the room's strategy for a
device, as its actions' `why` says it (`backup 18.5 while the pump
waits`); a device with no action still has its line.

| `Action` field | What it is                                                           |
| :------------- | :------------------------------------------------------------------- |
| `zone`         | the room's; nil for a system's mode                                  |
| `device`       | the device's label, or the system's                                  |
| `setting`      | `:mode`, `:power`, `:target` or `:setpoint`                          |
| `from`, `to`   | what it is (nil: unknown) and what it should be                      |
| `offset`       | what the translation added for the device's own sensor (nil: none)   |
| `why`          | the room's strategy, band and temperature; for a mode, its heat pump |

`why` reads `"comfort, +20.0..+26.0, at 18.5 (devices)"`, `(devices)`
when the temperature is the devices' average, `, +1.2 offset` after it
when the translation gave one. What overrode the strategy for that
device comes after the strategy: the [pump backup](strategies.md#pump-backup),
and a heat pump's [pump wait or urgent room](short-cycles.md#said-in-why); a system's mode reads `"source "` and
its heat pump's name.

`warnings` are `Notice`s ([warnings](warnings.md)), the translation's
`notes` after them as it gave them.

## Targets

A target or setpoint is put on the device's `step` and within its
`range`. One within a step of what the device holds, or already where
the wanted one lands, is left alone, so a translation's offset moving a
little does not move the device. A radiator not heating gets its least
target, `range`'s start else `least`; one already `:off` stays so; one
with neither is left as it is and said.

A unit reports the setpoint of the mode it is in. When its system
changes mode, the setpoint it will hold is not known, so the action's
`from` is nil and the setpoint is written; a unit with `ranges` gets it
within the range of the direction it will run in.

## Translation

A translation makes the band's side into what a device's own sensor
reads when the room holds it. It answers `target(room, device,
setpoint, mode)` with a `Target` (`celsius`, `gap`), `mode` being a
unit's direction and nil for a radiator, and `notes`, what it could
not translate. `AsIs`, the default, gives the band's side with no gap.

```ruby
# A valve reading 1.2 °C under the room; units left as they are.
class Warmer
    def target(_room, device, setpoint, _mode = nil)
        gap = device.label.start_with?("valve") ? 1.2 : nil
        P::Target.new(celsius: setpoint + gap.to_f, gap:)
    end

    def notes = ["unit:1: no offset learned yet"]
end

valve = P::Radiator.new(ref: "VA1", label: "valve:VA1", caps: gas_radiator,
                        temperature: 18.4, mode: :off, target: 17.0,
                        range: 5.0..25.0, step: 0.5)
living = P::Room.new(zone: "living", band: S::Setpoint.new(heat: 20, cool: 26),
                     strategy: :comfort, radiators: [valve], aircons: [])

result = P::Plan.new([living], translation: Warmer.new).run
result.actions.map { [it.setting, it.to, it.offset] }
# => [[:mode, :heat, nil], [:target, 21.0, 1.2]]
result.actions.last.why
# => "comfort, +20.0..+26.0, at 18.4 (devices), +1.2 offset"
result.warnings  # => ["unit:1: no offset learned yet"]
```

20 °C and the valve's 1.2 °C make 21.2 °C, on its 0.5 °C step 21.0 °C.
A note is the translation's own: a `String`, not a `Notice`.

## PumpState

What the caller knows of a heat pump, by its name in `pumps:`:

| Field          | What it is (default)                                                                                |
| :------------- | :-------------------------------------------------------------------------------------------------- |
| `held`         | a direction set outside the planner and held: `:heat`, `:cool`, or nil for neither; none by default |
| `running`      | whether its compressor runs now; nil, taken as whether one of its units is on                       |
| `switched_ago` | minutes since it last started or stopped (nil: unknown)                                             |
| `waited`       | whether the last plan had it wait (`Result#waited`; nil: unknown, taken as not)                     |

`held` decides the direction ([heat pumps](heat-pumps.md#a-direction-held));
`running` and `switched_ago` the [hysteresis](heat-pumps.md#changing-direction)
and the [least times](short-cycles.md#least-times); `waited` keeps the
[pump wait](short-cycles.md#the-pump-wait) through `wait_kept`.
