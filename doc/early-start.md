# Early start

A timetable holds the times its rooms are used: `07:30=wakeup` means
warm at 07:30. `EarlyStart` says whether a room starts a change ahead
of its time so it is in the band at the change, with which band and
strategy, and what is said. It has no clock: the caller gives the
minutes until each change and until its next plan, the rates it
learned, and the latch it keeps. The caller holds the band it gives in
a layer of its own in thermidor-schedule's stack, under the holds made
by hand, the open window and the guards; why, and ClimatControl's side:
[design/early-start.md](../design/early-start.md).

- [A step](#a-step)
- [What it takes](#what-it-takes)
- [The rules](#the-rules)
- [Costs](#costs)
- [Notes](#notes)

## A step

red-room at 05:00, 16.5 °C under a night band, 2.0 °C outside,
`07:30=wakeup` ahead. Its radiator warms it at 3.0 °C/h, losing 0.08 an
hour for each degree over the outside, 15 min before the room moves:
131 min to 19.8 °C, 0.2 under the wakeup band.

```ruby
valve = P::Radiator.new(ref: "VA1", label: "valve:VA1", caps: gas_radiator,
                        temperature: 16.5, mode: :heat, target: 17.0,
                        range: 5.0..25.0, step: 0.5)
red   = P::Room.new(zone: "red", band: S::Setpoint.new(heat: 17, cool: 27),
                    strategy: :comfort, radiators: [valve], aircons: [],
                    measured: 16.5, outside: 2.0)
rates = { heat: { radiators: P::Rise.new(base: 3.0, loss: 0.08, delay: 15) } }
wake  = S::Setpoint.new(heat: 20, cool: 25)
early = P::EarlyStart.new

early.start(red, ahead: [P::Ahead.new(minutes: 150, band: wake,
                                      strategy: :comfort)],
                 rates:, next_in: 10).ahead
# => nil
due = early.start(red, ahead: [P::Ahead.new(minutes: 140, band: wake,
                                            strategy: :comfort)],
                       rates:, next_in: 10)
due.band.to_s       # => "+20.0..+25.0"
due.strategy        # => :comfort
due.minutes.round   # => 131
due.notes.first.to_s
# => "red: early start for +20.0 in 140 min: needs 131 (radiators, 1.8 °C/h)"
```

At 150 min, starting at the next plan, 10 min on, is still in time:
nothing starts. At 140 it is not: the warm-up starts, both sides moved
to the wakeup's, as the latch will hold them.

## What it takes

`EarlyStart.new(settings:, strategy:)#start(room, ahead:, rates:,
next_in:, periods: nil)` gives a `Start`.

| Argument   | What it is                                                                                      |
| :--------- | :---------------------------------------------------------------------------------------------- |
| `room`     | the `Room` the plan would get, from the band in force without early start                       |
| `ahead`    | `[Ahead, ...]`: each change's `minutes` until it, `band`, `strategy`, and `started`              |
| `rates`    | `{ heat: { radiators:, units:, both: }, cool: { units: } }`, `Rise`s, any of them missing       |
| `next_in`  | minutes until the caller's next plan                                                            |
| `periods`  | `[Period, ...]`: from `minutes` on, `costs` and `excluded` as `Room`'s; nil, now's alone        |

`Rise`: `base`, °C/h at full call with the outside as warm as the room;
`loss`, what each °C of inside−outside gap takes off it, 1/h; `delay`,
minutes before the room moves; `gap`, the mean gap it was learned over,
standing for an outside not known. Learning them is the caller's.

`EarlyStartSettings`, one per room:

| Setting    | Default | What it is                                                                     |
| :--------- | :------ | :----------------------------------------------------------------------------- |
| `lead`     | 180     | the most minutes a change starts ahead                                         |
| `reach`    | 0.2     | how far inside its side (°C) the room is aimed at for the change               |
| `warmup`   | `:own`  | the strategy every warm-up runs; `:own`, the change's                          |
| `hurry`    | false   | whether a warm-up its strategy cannot bring in time runs quick instead          |
| `fallback` | nil     | the minutes ahead a change starts with no rate; nil, none                       |

`Start`: `band` and `strategy` to hold now (the room's own when nothing
starts), `ahead` the change it starts for (nil for none), `minutes` what
reaching the aim takes from now, `notes`.

## The rules

- **Only a side asking more** starts early: a higher heat side, a lower
  cool side. A change down never moves; nor a room already within
  `reach` of the side ahead.
- **The devices** are those the warm-up's strategy heats with at the
  band ahead (`Strategy.heat`), less any an energy rule caps under the
  aim; their classes pick the rate (`:radiators`, `:units`, `:both`, a
  missing `:both` taking the faster single). Cooling is the units'.
- **How long**: dT/dt = base − loss·(T − outside), segment by segment
  over the periods, after the delay. Under the band now, the room is
  taken as it is until the start; above it, coasting down to it.
- **When**: due once it is no more than `lead` ahead by the next plan
  and starting then would not be in time, so a warm-up starts up to one
  plan early, never one late. Late, it starts now and says so; out of
  reach, it starts `lead` ahead.
- **The latch**: the caller gives back the strategy of the warm-up it
  holds (`Ahead#started`); a started warm-up goes on, every side of
  the band ahead that asks more, whatever the room does or whether it
  can be read, and keeps its strategy. A side held past its aim, or
  without a rate, is held silently.
- **Which strategy**: `warmup`, or the change's; with `hurry`, quick
  when that one is late or capped and quick's devices are faster, chosen
  once when it starts.
- **Several changes**: each side moves to the most demanding of the due
  changes' sides asking more, all of them from the first start, as the
  latch then holds them; the highest heat side drives the strategy and
  `Start#ahead`. Sides closer than the deadband take the driver's band
  whole.

## Costs

Periods first fix the devices: an exclusion from 06:00 takes its class
out of the warm-up from then, under any strategy, so it starts sooner.
Under cheapest, they also choose the start: each start a plan apart, no
more than `lead` ahead, on cheapest's devices and on quick's, summed in
the room's own heat capacity at each period's costs (holding the band
now before it, full call to the aim, holding the aim after). Only the
starts in time count. The latest on cheapest's own devices is the
baseline; an earlier one, or quick's, wins only by
`StrategySettings#cost_margin`. A device without a cost in a period
leaves the start to the rate, said.

## Notes

`Start#notes` are `Notice`s, apart from a plan's warnings: their
`kind`, `zone`, and `ahead`, the change each is about. The caller adds
the clock time.

| Kind                 | Sentence                                                                  |
| :------------------- | :------------------------------------------------------------------------ |
| `:early_start`       | `red: early start for +20.0 in 140 min: needs 131 (radiators, 1.8 °C/h)`  |
| `:early_late`        | `red: early start for +20.0 late: needs 131 min, 60 left`                 |
| `:early_capped`      | `red: early start for +20.0 capped: needs 198 min, starts 180 ahead`      |
| `:early_unreachable` | `red: +20.0 out of reach of radiators at 2.0 °C outside: starts 180 ahead` |
| `:early_hurry`       | `red: early start for +20.0 on quick: quiet needs 131 min, quick 47`      |
| `:early_fallback`    | `red: early start for +20.0, 60 min ahead (no rate, fallback)`            |
| `:early_cheaper`     | `red: early start for +20.0, 150 min ahead: 32 % cheaper than at 110`     |
| `:early_uncosted`    | `red: early start for +20.0 by its rate: no cost for valve:VA1 at 60 min` |
| `:early_unrated`     | `red: no early start for +20.0: no rate for radiators`                    |
| `:early_unread`      | `red: no early start for +20.0: room temperature unknown`                 |
|                      | `red: early start for +20.0 held: room temperature unknown` (started)     |
