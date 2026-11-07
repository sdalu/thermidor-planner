# Short cycles

A heat pump's one compressor runs while any unit on it calls, and one
whose least output exceeds a mild day's load starts and stops over and
over. So [the planner](README.md) plans the units on one heat pump as
one, against it: `PumpCycle` takes each unit's target as its
[direction](heat-pumps.md) and strategy give it, and gives back a
target, nil for off, or `PumpCycle::KEEP`, the unit left as it is
(power and setpoint unwritten).

Its settings are the `PumpSettings` in the settings' `pump`, each off
until set:

| Setting         | Default | What it is                                                                     |
| :-------------- | :------ | :----------------------------------------------------------------------------- |
| `wait_above`    | nil     | °C outside from which the [pump wait](#the-pump-wait) holds                    |
| `wait`          | 1.0     | how far under its target a room starts a stopped heat pump                     |
| `min_on`        | nil     | minutes a started heat pump runs at least                                      |
| `min_off`       | nil     | minutes a stopped heat pump rests at least                                     |
| `urgent`        | 1.0     | °C past its band that ends a least time                                        |
| `backup_above`  | nil     | °C outside from which radiators lead ([strategies](strategies.md#pump-backup)) |
| `backup_within` | 1.0     | how far under its band a room still lets its radiators lead                    |
| `backup_kept`   | 0.5     | how far under `backup_above` radiators leading already keep the lead           |
| `backup_under`  | 0.5     | how far under its restart point a backup radiator sits ([waiting](#waiting))   |

`PumpSettings` refuses a negative value, and a nil `wait`,
`urgent`, `backup_within` or `backup_kept`, with `ArgumentError`
(`backup_under` nil is off). An unknown outside
temperature, room temperature or `switched_ago` leaves the plan as it
would be without the setting.

## The pump wait

The pump wait holds when the heat pump heats, `room.outside` is at or
above `wait_above` in every room on it that gives one (its units planned or
not: one unread still says the weather), at least one does, and every
room whose unit is planned has its temperature known.

- Stopped, the heat pump starts only once a room on it is more than
  `wait` under its unit's target; then every unit whose room
  is under its target starts with it, one run for all.
- Running, a unit whose room reaches its target goes off, and the last
  one stops the heat pump.

Whether it runs is `PumpState#running`, or, unknown, whether one of its
units is on.

### Waiting

Stopped with no room calling, the heat pump waits for its restart
point, `wait` under its unit's target. A radiator heating up
to there would hold the room above it, and the pump would never start:
a radiator the strategy or the effects step back behind the unit (a
solar surplus preferring electricity, say) heats no higher than
`backup_under` under the restart point, a safety net. The room falls
to the restart point, the pump starts and runs one long cycle, and the
radiator is back at its comfort gap. A radiator leading with the unit
or ahead of it is left; nil `backup_under` leaves the strategy's
target. Its `why` says `backup 18.5 while the pump waits`.

```ruby
band = S::Setpoint.new(heat: 20, cool: 26)
room = lambda do |zone, temperature, on: false|
    unit = P::Aircon.new(ref: zone, label: "unit:#{zone}", caps: heat_pump,
                         system: "system:1", source: "pump",
                         master: zone == "a", temperature:, on:,
                         mode: :heat, setpoint: 20.0, range: 18.0..30.0,
                         step: 0.5)
    P::Room.new(zone:, band:, strategy: :comfort, radiators: [],
                aircons: [unit], outside: 12.0)
end
mild = P::StrategySettings.new(pump: P::PumpSettings.new(wait_above: 8.0))
power = ->(rooms) { P::Plan.new(rooms, settings: mild).run.actions
                                .select { it.setting == :power }
                                .map { [it.device, it.to] } }

waiting = [room.("a", 19.5), room.("b", 19.5)]
power.(waiting)  # => []
starting = [room.("a", 18.9), room.("b", 19.5), room.("c", 20.2)]
power.(starting)  # => [["unit:a", true], ["unit:b", true]]
running = [room.("a", 19.5, on: true), room.("b", 20.1, on: true)]
power.(running)  # => [["unit:b", false]]
```

At 19.5 °C neither room is more than a degree under its 20 °C target:
nothing starts. Once one is, every room under its target starts with
it; a room already warm does not. Running, the room that reached its
target lets its unit go.

## Least times

`PumpState#switched_ago` is the minutes since the heat pump last
started or stopped.

- Started less than `min_on` ago: its units that are on are left as
  they are, power and setpoint, unless a unit's energy is excluded now,
  it cannot cool when the heat pump cools, it runs another direction,
  or its room is more than `urgent` past its band the warm way.
- Stopped less than `min_off` ago: none of its units is switched on or
  given a new setpoint, and its rooms needing heat are heated by their
  radiators meanwhile, until a unit off whose room is more than
  `urgent` past its band the cold way starts it, which ends the rest
  for all.

Holding a unit's power is said, as a `:kept` [warning](warnings.md):
running, when a unit the plan would switch off is kept on; stopped,
when one it would switch on is kept off.

```ruby
valve = P::Radiator.new(ref: "VA", label: "valve:VA", caps: gas_radiator,
                        temperature: 19.5, mode: :heat, target: 20.0,
                        range: 5.0..25.0, step: 0.5)
quiet = room.("a", 19.5, on: true)
            .with(strategy: :quiet, radiators: [valve], outside: nil)
least = P::StrategySettings.new(pump: P::PumpSettings.new(min_on: 15,
                                                          min_off: 10))
started = ->(ago) { { "pump" => P::PumpState.new(running: true,
                                                  switched_ago: ago) } }

early = P::Plan.new([quiet], settings: least, pumps: started.(5)).run
early.actions  # => []
early.warnings  # => ["pump: kept running: started 5 min ago, at least 15"]
later = P::Plan.new([quiet], settings: least, pumps: started.(20)).run
later.actions.map { [it.device, it.setting, it.to] }
# => [["unit:a", :power, false]]
```

Under `quiet` the loud unit rests: started 5 minutes ago, it keeps
running until its 15 are done.

```ruby
cold = room.("a", 19.5).with(radiators: [valve.with(target: 17.0)],
                             outside: nil)
stopped = { "pump" => P::PumpState.new(running: false, switched_ago: 3) }

resting = P::Plan.new([cold], settings: least, pumps: stopped).run
resting.actions.map { [it.device, it.setting, it.to] }
# => [["valve:VA", :target, 20.0]]
resting.warnings  # => ["pump: kept stopped: stopped 3 min ago, at least 10"]
```

Stopped 3 minutes ago, the heat pump rests its 10: the room heats with
its radiator meanwhile, as if it had no unit.

## Said in why

An action the heat pump's measures changed says which in its `why`,
after the strategy: `pump wait` for a unit off that the strategy would
have heat, `urgent, run ended` for a unit switched off within its
least run, its room too warm, and `rest ended: a urgent` for every unit
heating once zone `a` ended the rest. A unit held (`KEEP`) gets no
action: the `:kept` warning says it.
