# Early start (proposed, not built)

Status: built on 2026-11-10 (doc/early-start.md says how it is used),
asked for by the user on 2026-11-08 through the ClimatControl session,
amended the same day with the user's decisions
([Decisions](#decisions)) and a review's fixes. What the build changed
is under [Built](#built).

- [What it is](#what-it-is)
- [Where it sits](#where-it-sits)
- [The planner's step](#the-planners-step)
- [The rate model](#the-rate-model)
- [Schedule and planner](#schedule-and-planner)
- [ClimatControl's part](#climatcontrols-part)
- [Costs](#costs)
- [Not in the first version](#not-in-the-first-version)
- [Tests](#tests)
- [Release and pin](#release-and-pin)
- [Decisions](#decisions)
- [Built](#built)

## What it is

A timetable holds the times its rooms are used: red-room `07:30=wakeup`
means warm at 07:30, not warming from 07:30. Early start begins the
change ahead of its time, so the room is in the band at the transition.
It needs three things: when the change comes and to what (the
schedule), how fast this room warms with these devices (learned from
the house), and how long that takes from where the room is now. The
last is planning logic, so it is the planner's. It stays without a clock
and without learning (DESIGN.md, "What is the planner's"). The caller
says how many minutes away the change is and passes the rates it
learned. The planner turns them into a decision: start now or not, with
which band and which strategy.

Only a side that asks for more starts early: a higher heat side, or a
lower cool side. A change down to eco or night never moves. Stopping
early ahead of a drop is optimum stop, a separate feature (later).

## Where it sits

The timetable stays what it is. Early start is a layer of the caller's
in thermidor-schedule's stack. Schedule's README already allows this: "a
layer is anything answering `apply(zone, now, below)`". No schedule code
is needed. ClimatControl builds a `Layers::Manual.new(entries,
source: "early-start")` with one `Manual::Entry` per zone that starts
early. Its `preset` is an anonymous `Preset.new(setpoint: band)` holding
the step's band. Its `strategy` is the step's, which `Entry` runs
through `Schedule.strategy`, so a warm-up strategy must be one the
schedule is configured with. `starts_at` is when the warm-up started,
`ends_at` the change it starts for. It goes here:

```text
Clamp          limits both sides, as now
Guard          limits, as now          ┐ these win over early start
OpenWindow     a window open           │ by being above it: a window
Boost          a push by hand          │ opened mid-warm-up stops it,
Manual         a setting by hand       ┘ a guard caps it
early-start    the planner's step      <- new, the caller's layer
Away           an away period with an end
Calendar       another kind of day
Timetable      the times rooms are used
```

So the question "which layer decides" has a simple answer: the layer's
place in the stack. A hold made by hand (manual, boost), or an open
window, sits above early start and overrides it while it lasts. The
warm-up goes on below, and shows again when the hold ends before the
change. A guard and the clamp limit the early band as they limit any
other. Early start sits above away and calendar, so the return from an
away period with an end is warmed for (`away:auto` has no end, so no
change ahead). The layer is active only from now until the change: at
the change the timetable gives the same band itself.

A round, in ClimatControl:

```text
base stack (no early-start layer)
  ├─ resolve(zone, now)            -> the band now, its source
  └─ Upcoming#changes(zone, now, now + lead + next_in)
                                   -> the changes ahead, each its band
planner: EarlyStart#start(room, ahead:, rates:, next_in:, periods:)
                                   -> Start: band, strategy, notes
store: write, keep or clear the zone's early-start entry
full stack (with the layer) resolve(zone, now)
                                   -> Room's band and strategy
planner: Plan.new(rooms, ...).run  -> actions, unchanged
```

The step reads the base stack, not the full one: with the layer in,
the band now would already be the early one, and the step would merge
with itself.

## The planner's step

`Plan` does not change. The step is a new part, run before it, room by
room, and gives the band and strategy the layer holds.

### Types

```ruby
# How early start runs in a room. lead: the most minutes a change is
# started ahead; reach: how far inside its side (°C) a room counts as
# in the band, aimed at for the change's time; warmup: the strategy
# every warm-up runs, :own for the change's own; hurry: whether a
# warm-up that cannot be in time on its strategy runs quick instead;
# fallback: the minutes ahead a change starts with no rate for its
# devices (nil: it does not start).
EarlyStartSettings = Data.define(:lead, :reach, :warmup, :hurry,
                                 :fallback)
#   defaults: lead: 180, reach: 0.2, warmup: :own, hurry: false,
#             fallback: nil

# A change ahead, as the caller found it: minutes until it, the band
# and strategy it brings; started: the strategy of the warm-up the
# caller holds for it already (the step said so at an earlier plan),
# nil when none: at once the latch and the strategy chosen.
Ahead = Data.define(:minutes, :band, :strategy, :started)

# How fast a room's temperature moves with a set of devices at full
# call, in °C/h: base, the rate with the outside as warm as the room;
# loss, what each °C of inside-outside gap takes off it (cooling: adds);
# delay, minutes before the room starts to move (water warming in a
# radiator); gap, the mean inside-outside gap it was learned over, used
# when the outside is not known.
Rise = Data.define(:base, :loss, :delay, :gap)

# What the step gives a room: band and strategy to hold now (the band
# now and its strategy when nothing starts); ahead: the Ahead it starts
# for, nil when none; minutes: what reaching it takes, nil when no rate;
# notes: Notices, said whether or not it starts.
Start = Data.define(:band, :strategy, :ahead, :minutes, :notes)

EarlyStart.new(settings: EarlyStartSettings.new, strategy: StrategySettings.new)
          .start(room, ahead: [Ahead, ...], rates:, next_in: 10,
                 periods: nil)
# rates: { heat: { radiators: Rise, units: Rise, both: Rise },
#          cool: { units: Rise } }, any of them missing
# next_in: minutes until the next plan (the caller's cadence)
```

`room` is the `Room` the plan would get, built from the base stack's
decision now: its band, strategy, devices, temperature, outside,
excluded energies and effects. `strategy:` resolves house aliases and
comfort's gap as the plan does. The settings are the room's: the
caller builds them from the house's values and the zone's own
([ClimatControl's part](#climatcontrols-part)).

### The rules

1. **The room's temperature** is `Room#temperature`, the measured one
   else its devices'. With none, nothing starts (note
   `:early_unread`).
2. **Which sides**: for each `Ahead`, the heat side starts early when
   it is above the band now and the room is under it less `reach`. The
   cool side starts early when it is below the band now and the room is
   above it plus `reach`. Anything else is no early start for that
   `Ahead`, unless it is `started` (rule 6). This covers a band ahead
   that is lower, or a room not yet started and already warm enough.
3. **Which devices**: heating, those the warm-up's strategy (rule 8)
   has heat at its band, by `Roles` with the room's excluded energies and effects
   now. Any with an offset counts, so comfort's gap-behind devices too,
   since far under the band they all call. A device an energy rule
   caps (`Effects`) under the aim is left out: it cannot bring the
   room there. Their classes pick the rate:
   radiators alone `:radiators`, units alone `:units`, both `:both`.
   Cooling is always the units' (`rates[:cool][:units]`).
4. **The rate**, with no `Rise` for that set: for `:both`, the faster of
   `:radiators` and `:units`. That is slower than both together, so it
   starts early enough. With none, nothing starts for it (note
   `:early_unrated`). With `fallback` set, it starts `fallback` minutes
   ahead instead (no more than `lead`), said (`:early_fallback`); late
   and hurry do not apply, having no rate to judge by.
5. **How long** (minutes), from the room's temperature `t0` to the aim
   `t1` (heat side less `reach`; cool side plus it), with the outside
   `o`. When `room.outside` is nil, `o` is taken as `t0 − Rise#gap`,
   the gap the rate was learned over. Heating,
   dT/dt = base − loss·(T − o):
   - loss 0: `delay + 60 · (t1 − t0) / base`;
   - else `delay + 60 / loss · ln((base − loss·(t0 − o)) / (base −
     loss·(t1 − o)))`;
   - a denominator at or under 0 means the room settles under the aim
     with these devices at this weather: unreachable (note
     `:early_unreachable`), started at `lead`.

   Cooling mirrors this, dT/dt = −base − loss·(T − o).
6. **When**: the ideal start is `ahead.minutes − need` minutes from
   now, but no more than `lead` ahead: `max(ahead.minutes − need,
   ahead.minutes − lead)`. The `Ahead` is due when that is at or under
   `next_in`. Waiting for the next plan would then start after the
   ideal time, so a start is up to one cadence early, never one late.
   With `started` set it stays due whatever the sum says, rule 2
   included. A room
   warming faster than its rate would otherwise drop back to the band
   now and go back and forth. This latch is the caller's to keep and give
   back, as `PumpState#waited` is: the planner keeps no memory of its
   own plans.
7. **Late**: when `need > ahead.minutes`, it starts now (it is due) and
   says by how much it will miss (note `:early_late`).
8. **Which strategy**: the warm-up runs `warmup`, or the change's own
   strategy when `warmup` is `:own`. Its devices (rule 3) give the rate
   and the due time. The choice below is made once, at the plan where
   the `Ahead` first falls due (`started` nil), and `started` keeps it
   after: no switch to quick mid-warm-up, none back.

   With `hurry` on, when that strategy's set cannot bring the room in
   by the change (late, rule 7; capped, rule 9; unreachable, rule 5)
   and quick's set would do better (sooner, or reaching at all), the
   warm-up runs quick, said (`:early_hurry`). Under cheapest the test is
   on the latest in-time candidate ([Costs](#costs)), so cost is tried
   first. The due time stays the warm-up strategy's own, so hurrying
   never starts later than the strategy it replaces.

   The user's three wishes: quick at once is `warmup: :quick`; quick
   only when the early start would fail is `hurry` on; never quick is
   both defaults.
9. **Capped**: when `need > lead`, it starts `lead` ahead and says so
   (note `:early_capped`).
10. **Several changes ahead** (two transitions close, a short eco
   between two comforts): each `Ahead` is judged on its own. The band
   is the band now with each side moved to the most demanding due
   `Ahead`'s: the highest heat side, the lowest cool side. If the two
   sides would come closer than the deadband, the driving `Ahead`'s
   band is taken whole. The strategy is the `Ahead`'s whose heat side
   drives (the nearer one on a tie), else the cool side's, and
   `Start#ahead` is that `Ahead`. A dip shorter than its warm-up is
   heated through, which is what the user's times ask. When a later
   `Ahead` takes over as driver, the caller's entry moves to its time,
   and the earlier one's latch goes with it: from then on the later
   one drives, which is the one that asks more.
11. **Humidity bounds** stay the band now's.
12. **Held devices** (`room.held`, switched by hand) are left out by
    `Roles` as in the plan, so a held radiator does not count towards
    the rate. A room with every heating device held starts nothing
    (`:early_unrated`, no set).

### Notes

`Start#notes` are `Notice`s: their own list, not `Result#warnings`.
Most are information, not failures, and the caller chooses what to
show. Each has `zone` and `kind`. The texts are proposed; the planner
has no clock, so a time of day is the caller's to add.

| kind                 | text (proposed)                                                       |
| :------------------- | :-------------------------------------------------------------------- |
| `:early_start`       | `early start for +20.0 in 140 min: needs 131 (radiators, 1.8 °C/h)`   |
| `:early_late`        | `early start for +20.0 late: needs 131 min, 90 left`                  |
| `:early_capped`      | `early start for +20.0 capped: needs 230 min, starts 180 ahead`       |
| `:early_unreachable` | `+20.0 out of reach of radiators at 2.0 °C outside: starts 180 ahead` |
| `:early_hurry`      | `early start for +20.0 on quick: comfort needs 230 min, quick 150`    |
| `:early_fallback`    | `early start for +20.0, 60 min ahead (no rate, fallback)`             |
| `:early_unrated`     | `no early start for +20.0: no rate for radiators`                     |
| `:early_unread`      | `no early start for +20.0: room temperature unknown`                  |

### A worked case

red-room at 05:00, night band `+17..+27`, 16.5 °C, 2.0 °C outside;
`07:30=wakeup` brings `+20..+25` under comfort, its radiator alone
taking part. The radiators' `Rise` is base 3.0, loss 0.08, delay 15.
The aim is 19.8. The rate is 1.84 °C/h at 16.5 and 1.58 at 19.8, so it
needs 15 + 60/0.08 · ln(1.84/1.58) ≈ 131 min. At 05:00 the start falls
19 min from now, above the 10-min cadence, so nothing starts. At 05:10
it falls 9 min from now and is due: the layer holds `+20..+27`/comfort
until 07:30, and the plan heats the radiator to 20.

### With the plan and the strategies

The step only chooses a band and a strategy; the plan carries them out
as any other. So effects, energies excluded, the translation, the pump's
direction, its wait and least times, cheapest's costs: everything
applies to the early band unchanged. Two consequences, said and not
fixed in the first version:

- The step picks the rate from the devices the strategy would run. It
  does not know whether the heat pump will run that way: a pump voted
  to cool, or waiting in mild weather, leaves the units out, and a
  `:both` rate is then too fast. The plan's own warnings say it. A late
  room is the result, never a cold one.
- An exclusion that begins between now and the change (a Tempo red
  peak from 06:00) is not foreseen: the set is judged by now's. The
  periods ahead ([Costs](#costs)) fix it.

## The rate model

What ClimatControl learns, stores and passes. The planner checks only
that a `Rise` holds together (base > 0, loss ≥ 0, delay ≥ 0).

- **Units**: °C/h for `base` and the rate. `loss` in 1/h (°C/h per °C
  of gap). `delay` in minutes. `gap` in °C.
- **Keys**: per zone, per direction (`:heat`, `:cool`), per device set
  (`:radiators`, `:units`, `:both`; cooling `:units`). A set is what ran,
  not a device: two radiators in a room are one `:radiators`.
- **Shape**: linear in the inside−outside gap, `rate = base − loss ·
  gap`. That is Newton's cooling with the devices' power taken as fixed.
  Two numbers carry over to cold days the house has not seen yet, where
  bins would hold no data. Fitted by least squares over warm-up samples.
  When the samples' gaps span under about 6 °C, `loss` cannot be told
  from noise: fit `base` alone, `loss` 0, and `gap` their mean.
- **Samples**: stretches where the set runs at full call. Valves open
  (MadHouse's valve %, at or above a level the house names). A unit on
  in the direction with its setpoint a degree or more past the room.
  Started at least 0.5 °C under the band. Unbroken for at least 20 min,
  window shut. Each 15-min window gives a rate and a gap. `delay` is the
  median time from a stretch's start to the room's first +0.1 °C.
- **No rate yet**: no early start for that set, said (`:early_unrated`):
  a wrong default would heat at the wrong time unseen, a note is seen.
  The `fallback` option (off by default) starts a fixed number of
  minutes ahead instead, only while no rate is passed.
- **Staleness**: the caller's policy, since the planner has no clock.
  Recommended: refitted nightly over the last 28 days. Not passed when
  it rests on fewer than 4 stretches, or its newest is more than 21
  days old (the season moved).

## Schedule and planner

- **The changes ahead** come from the schedule, as ClimatControl's
  `Upcoming#changes(zone, now, now + lead + next_in)` already finds
  them. That is the base stack resolved at each `Stack#wake_at`. Each
  `Change` becomes an `Ahead`: `minutes` ((`at` − now) / 60),
  `change.to.setpoint`, `change.to.strategy`. Its band is the full base
  stack's at that time: a guard or a hold at the change's time is
  already in it.
- **Who asks "decide at T"**: ClimatControl, through `Upcoming`. The
  planner never sees a time. The schedule gives no new call: its
  `Layers::Manual` with a `source:` already holds the entries.
- **The planner's dependency** on thermidor-schedule stays `Setpoint`:
  the step builds the merged band as one, which refuses sides closer
  than the deadband (rule 10 avoids that).

## ClimatControl's part

`ClimatControl::Planning`, at each round (the watch's `every`, 10 min
now):

1. For each zone with early start on: the base stack's decision now.
   If its source is a hold that sits above the layer (manual, boost,
   open-window), skip the step: the layer would be hidden anyway. Keep
   any entry already there, so the warm-up resumes when the hold ends.
2. The changes ahead within `lead + next_in`, as `Ahead`s.
   `started` is the stored entry's strategy for the change whose time
   matches its `ends_at`, nil for the others.
3. `EarlyStart#start` with the `Room` the plan would get and the
   zone's rates. `next_in` is `watch.every / 60`. With costs, the
   `Period`s over `lead + next_in`, from the energy module's verdicts
   at each tariff change (hours, Tempo colour, the rules' exclusions).
4. Store: an entry when the step starts one (`ends_at` the driving
   change's time), rewritten when its band moved or another change
   took over as driver (rule 10). Its strategy is the latch's and does
   not move. An entry is cleared only when:
   - its change is no longer ahead (the timetable edited);
   - its `ends_at` is past;
   - the step judged the room and started nothing, with `started` nil.
   An entry held with `started` set survives a round that could not
   judge (`:early_unread`, `:early_unrated`): one unread round
   mid-warm-up would otherwise clear the latch, and the next round,
   finding the room past its aim, would drop it back to the band now
   to cool, then start again.
5. The full stack (with the `early-start` layer from the store) for
   the `Room`s, then `Plan` as today. `Store#stack(at)` is today the
   one builder, and `Upcoming` and the manual ends read it, so the
   full stack is a second builder (or a flag on it) that those two
   never use.

- **Settings**, as ClimatControl's others: a house value in the
  settings table, which a zone may own through `Store::ZoneSettings`
  (its `NAMES`), the zone's read over the house's at each decision.
  Durations in seconds and switches `on`/`off`, as `boost.for` and
  `away.auto` are; the step's minutes are made from them.

  | setting          | values                      | default | a zone may own |
  | :--------------- | :-------------------------- | :------ | :------------- |
  | `early.start`    | `on`, `off`                 | `off`   | yes            |
  | `early.lead`     | seconds                     | 10800   | yes            |
  | `early.reach`    | °C                          | 0.2     | yes            |
  | `early.warm-up`  | `own`, a strategy           | `own`   | yes            |
  | `early.hurry`   | `on`, `off`                 | `off`   | yes            |
  | `early.fallback` | seconds, unset for none     | unset   | yes            |
  | `early.fit-days` | days of history fitted      | 28      | no             |
  | `early.fit-stretches` | the fewest stretches   | 4       | no             |
  | `early.stale-days` | days without a stretch    | 21      | no             |
  | `early.fit-span` | °C of gaps to fit `loss`    | 6       | no             |
  | `early.full-call` | valve % counted as full call | the house's | no      |

  Opt-in per zone is `early.start` left `off` in the house and set `on`
  by each zone that wants it; `on` in the house with `off` in a zone
  opts the zone out. A bedroom can own `early.warm-up` `own` while the
  house warms up on `quick`. `early.warm-up` must name a strategy the
  schedule is configured with (rule 8 and `Manual::Entry`). The rates
  table (zone, direction, set, base, loss, delay, gap, stretches,
  fitted_at), filled by a nightly fit command, is per zone already.
- **Shown**: the notes in the plan's output and the watch's log, with
  the change's clock time added (`red-room: early start for +20.0 at
  07:30, from 05:10`). The zone's decision shows source
  `early-start` until the change, so `/strategy`, `schedule show` and
  the API say why the band moved.
- **Unchanged**: `Upcoming` keeps reading the base stack, so the
  changes it lists are the user's times. `Drifts` compares devices with
  what was applied, so an early target is no drift. Trimming should be
  checked against a band that is the layer's.

## Costs

Designed on 2026-11-08 at the user's request, and in the first
version (the user's decision).

### By the strategy, no flag

Cost-aware timing is cheapest's, with no new flag. The change ahead's
strategy already says what the house wants of that change, and early
start runs it, or `warmup` when set (rule 8):

| warm-up strategy | when it starts                                         | on which devices    |
| :--------------- | :----------------------------------------------------- | :------------------ |
| `cheapest`       | the cheapest start within `lead` that reaches the aim  | the cheapest, period by period, or quick's when that costs less |
| `comfort`        | as late as the rate allows (rule 6)                    | the gentlest first  |
| `quiet`          | as late as the rate allows                             | the quiet ones      |
| `quick`          | as late as quick's rate allows                         | all at once         |

A flag of its own (cost timing under every strategy) would have a
comfort room heat from 04:00 on cheap hours. That runs against what
comfort was chosen for, and would be one more setting saying what the
strategy already says. `warmup: :quick` takes cheapest off a warm-up
as it takes any other strategy. With `hurry` on, the cheapest start in
time is judged first, and quick replaces it only when no start on
cheapest's set is in time.

### What the caller passes: periods ahead

`room.costs` and `room.excluded` are now's. A warm-up spans up to
`lead`, across a tariff's hours. The caller passes what holds over the
window, as the energy module already judges it:

```ruby
# From minutes from now until the next Period: what a kWh of heat
# costs from each device, by label (as room.costs), and the energies
# excluded (as room.excluded). The first is at 0, now's.
Period = Data.define(:minutes, :costs, :excluded)

EarlyStart#start(room, ahead:, rates:, next_in:, periods: nil)
# periods nil: now's alone (room.costs, room.excluded), as without costs
```

A green Tempo day is two periods (off-peak until 06:00, peak after). A
red day differs only in the peak's costs, or in electricity excluded
from 06:00 when a rule says so. The caller knows tomorrow's colour from
the evening before, so a warm-up that starts before midnight sees it
too.

### Exclusions ahead, under every strategy

Periods are first a matter of correctness, not cost. Under any strategy,
the warm-up is followed period by period: its device set is the one
`Roles` gives with that period's costs and exclusions, at that set's
`Rise`. On a red day with electricity excluded from 06:00, a `:both`
warm-up becomes `:radiators` at 06:00. The time needed counts that, so
the start comes earlier and the room is no longer late. Rule 5's closed
form applies segment by segment (Newton's law has one per segment).

A period may leave the warm-up no device at all: an electric-only room
with electricity excluded on a red day. That segment is the room
coasting, dT/dt = −loss·(T − o), at no cost. It counts in the time
needed like any other, so the start comes before it, and a room that
cannot make up the loss afterwards is late or capped, said as such.

### Cheapest: choosing the start

The same `Rise` gives the heat a warm-up takes, in the room's own heat
capacity (°C of room): at full call, `base` an hour; holding at a
temperature T, `loss · (T − o)` an hour. The capacity is the same for
every start compared, so it cancels: no kWh, no new figure to learn.
`room.costs` are per kWh of heat, so a heat pump's COP is already in
them. For each candidate start, from the latest (rule 6) back to `lead`
ahead, a cadence (`next_in`) apart, the step sums from now to the
change:

1. before the start, holding the band now (or coasting down, free,
   when the room is above it), on cheapest's devices of each period;
2. from the start, full call on that period's cheapest set until the
   aim (its `delay` included: the devices run through it), then
   holding the aim until the change;

each period's heat at its devices' cost. Only candidates that arrive in
time count, on either set. The cheapest start wins. An earlier one wins
over the latest only when its sum is under the latest start's by at
least `StrategySettings#cost_margin`, a fraction of that sum, the
margin cheapest already uses for its lead. When no candidate is in
time, the warm-up starts as rule 6 says, is late (`:early_late`), and
hurry (rule 8) applies. Ties go to the later start, so the room is not warm longer
than it pays for. The chosen start is due as in rule 6; the latch
(`started`) holds it as before.

### Cheapest may warm up on quick

Quick can cost less than cheapest's own devices. Its dearer device adds
heat at a higher price, but the room warms in less time, so it starts
later and spends less time warm, losing less heat. It wins when the
cheapest device is slow against the room's loss (a cold night, a weak
heat pump) and the prices are close. It also wins when quick fits the
whole warm-up into an off-peak hour that cheapest's devices alone
cannot. So under cheapest, quick's set is a candidate too: each start
is summed on cheapest's set and on quick's, and the cheapest pair wins.
Quick wins only by `cost_margin` as well, so the room does not switch
for a cent. Quick's full call is priced by each class's share of the
heat, `base` of `:radiators` against `base` of `:units` (within a class,
its devices alike). Without both single rates, quick cannot be priced
and is no candidate. A warm-up that picks quick says so
(`:early_cheaper`, "on quick"). Like rule 8, the choice is made once,
when it falls due, and `started` keeps it. This is cost, not hurry: a
cheapest warm-up on quick is one where quick costs less, in time or
not.

### A red day

On a red day, the start that wins is the one that heats on the heat pump
in the off-peak hour and holds on gas after 06:00. That beats waiting
for 06:20 and heating on gas alone, once the saving clears the margin.

Without a cost for every device cheapest would run in some period,
cheapest itself guesses (heat pumps first), and so would any sum built
on it. Nothing is shifted: the latest start (rule 6), said (note
`:early_uncosted`). The device set still follows the periods.

New notes:

| kind              | text (proposed)                                                    |
| :---------------- | :----------------------------------------------------------------- |
| `:early_cheaper`  | `early start for +20.0, 150 min ahead: 18 % cheaper than at 90`    |
|                   | `early start for +20.0 on quick, 70 min ahead: 9 % cheaper than cheapest's` |
| `:early_uncosted` | `early start for +20.0 by its rate: no cost for unit:1 after 06:00` |

### Not with this

- **Storing heat**: heating past the change's band in cheap hours to
  coast through a peak. It would raise a band the user set, so not
  without the user's say.
- **Optimum stop** stays apart, below.

## Not in the first version

- **Optimum stop**: letting the room coast before a change down,
  ending heating early. It is the same rate model with the room's
  free-fall rate (devices off) as a fourth set.
- **Learning in the planner**, never: rates stay the caller's.
- **The pump's view** of the warm-up (rule 3's first consequence): the
  step run inside `Plan`, after the pump's direction and wait, would
  pick the right set. That costs folding it into `Plan#run`.

## Tests

The planner's suite would hold, for `EarlyStart`, each with rooms built
by hand as now:

- the worked case: not due 150 min ahead, due 140 min ahead, band
  and strategy, the `:early_start` note's text;
- the formula: loss 0 against the linear time; a loss against the
  closed form; `gap` used when `outside` is nil; delay added;
- unreachable (base ≤ loss · gap at the aim): started at `lead`, noted;
- capped at `lead`; late; the notes;
- `warmup`: `:own` runs the change's strategy; `:quick` runs quick,
  due by quick's rate; a strategy the room's devices rank differently
  (quiet) gives its own set;
- `hurry` off: late, capped or unreachable, the strategy kept; on:
  quick at the first due plan only when the strategy is not in time and
  quick's set does better, `:early_hurry`, due time the strategy's;
  kept by `started` after, never switched mid-warm-up;
- fallback nil: no rate, no start; fallback set: `fallback` minutes
  ahead, capped by `lead`, noted, no hurry;
- `started` keeps an `Ahead` due once the room passed its aim, over
  rule 2;
- a device capped under the aim by an energy rule left out of the set;
- `outside` nil: `o` taken as `t0 − gap`;
- a lower band ahead, and a room already within `reach`: nothing moves;
- a heat side ahead higher and a cool side lower: only the heat side
  moves, the cool side kept; deadband kept by taking the band whole;
- two close changes: the higher heat side drives, its strategy and
  `Ahead`; a short dip heated through;
- device sets: comfort with a radiator and a unit gives `:both`; quiet
  with a loud unit gives `:radiators`; an excluded energy drops its
  class; `:both` missing falls back on the faster single; none: no start;
- held devices left out of the set; every one held: no start;
- cooling: a lower cool side ahead, units' rate, rule by rule as heat;
- no temperature: `:early_unread`;
- `Rise`, `Ahead` and settings refusing what does not hold together
  (negative lead, reach, base);
- the doc page's examples run (doc/early-start.md, once built, by
  test/doc_examples_test.rb).

With costs:

- periods: an exclusion from 06:00 turns `:both` into `:radiators` at
  06:00, and the start comes earlier, under comfort too; a period with
  no device left coasts, free, and counts in the time;
- cheapest: the off-peak start chosen over the latest when it saves
  more than `cost_margin` of the latest's sum, the latest kept when it
  does not; a tie goes later; holding before the start priced, the
  delay priced at full call; coasting above the band now free; a
  candidate not in time never chosen; none in time: `:early_late`,
  then hurry;
- a device without a cost in a period: the latest start,
  `:early_uncosted`;
- cheapest on quick: quick's set chosen when its sum is lower by
  `cost_margin` (a slow cheap device on a cold night), not otherwise;
  no single rate, no quick candidate; kept by `started`;
- comfort, quiet and quick ignore costs for the start;
  `warmup: :quick` takes cheapest off; with `hurry` on, the cheapest
  start in time is judged first.

ClimatControl's suite: the layer's place (a manual hold hides it, an
open window stops it, a guard caps it), the latch through the store,
kept over an unread round, moved with a new driver, cleared on an
edited timetable, the settings read zone over house, `early.warm-up`
refused for a strategy the schedule does not know, the notes' clock
times.

## Release and pin

New public API, nothing renamed: a minor release, 0.5.0, the owner's to
tag. ClimatControl's pin move needs: its Gemfile on `v0.5.0`, its gate
run against this tree before (CHECKLIST.md), then its own part above.
thermidor-schedule needs no release for it.

## Decisions

The user's, on 2026-11-08:

1. No rate yet: no early start, said; a fixed fallback lead as an
   option, off by default (`fallback`, rule 4).
2. Quick: the user's three wishes (quick at once, quick only when the
   early start would fail, never quick, the default), decided when the
   early start is first asked for and never later. First written as one
   three-valued setting; reworked into `warmup` and `hurry` (rule 8),
   since cheapest's cost choice overlapped it.
3. The return from an away period with an end is warmed for: the layer
   above Away.
4. Early start is opt-in per zone (`early.start`, a zone's own).
5. Costs through cheapest only, no flag of their own
   ([Costs](#costs)).
6. Costs in the first version.
7. Early start's settings follow ClimatControl's: house values a zone
   may own, as `boost.for` and the open window's are.

Defaults the user may change, not decided:

- `reach` 0.2 °C, `lead` 180 min (10800 s);
- the rate fit: full call at a valve % the house names, a 28-day
  window, at least 4 stretches, stale after 21 days, `loss` fitted only
  over a 6 °C span of gaps.

## Built

What building it changed in this design, 2026-11-10:

- **`hurry`, not `rescue`**: `rescue` is a Ruby keyword, so the setting
  is `hurry` on both sides: `EarlyStartSettings#hurry`, ClimatControl's
  `early.hurry`, the note `:early_hurry` (the user's choice).
- **The latch holds every side asking more**, as rule 6 says. The
  build first held only the side nearer the room, judged by the middle
  of the band ahead; a bug hunt showed a warm-up overshooting that
  middle flipped the latch to the other side every plan (20..27, then
  17..25, then back). A cool side held during a heating warm-up does
  nothing to a room under it, so holding both is safe.
- **A held side says nothing** once past its aim or without a rate: no
  "no early start" for a warm-up that goes on.
- **Unread is said once**, on the heat side (a band's only side when it
  has one), not once per side; a warm-up held unread says it is held.
- **The first start gives the band the latch holds**: every side of a
  due change asking more, not only the side with work to do, so the
  caller's entry is written once, not rewritten at the next plan
  (ClimatControl's tests found it).
- **Each note carries its change** (`Notice#ahead`), so the caller ties
  it to the change's time without asking the step again.
- **`hurry` is a boolean**, refused otherwise: a setting's text `"on"`
  would have been read as off.
- **The cost baseline** is the latest start in time on the warm-up's own
  devices, quick's latest only when its own are never in time: quick's
  latest, the dearest, made every earlier start look cheap.
- **A period's set without a rate** coasts at the first set's loss
  rather than ending the warm-up: a slower course, an earlier start.
- **Cooling** is timed by its rate alone: no periods, costs or hurry.
- **The time before a start**: under the band now the room is taken as
  it is; above it, coasting down to it at the first rate's loss.

