# Design

## What is the planner's, and what the caller's

The planner turns a room's band and strategy, and what its devices read,
into actions. Everything that needs a particular house stays with the
caller: finding the devices and reading them, the energy rules and
when they hold, learning how far a device's own sensor reads from the
room, writing the actions, keeping what was written. What crosses the
boundary is plain data (`Room`, `Radiator`, `Aircon`, `Action`) and two
ducks: a device's `caps`, and a translation. So the planner has no
connection, no database and no clock of its own, and its tests build
rooms by hand.

It came out of ClimatControl, where it was written against tado
thermostats and Airzone units. What made it theirs was naming, not
logic: a device's label built from a tado serial, an Airzone system
named from its host and number, tado's least target, the sensorium
device names a translation looks up. Each became a field the caller
fills in (`label`, `system`, `least`, `step`) or a role (`:radiator`,
`:aircon`) the caller maps to its own names.

## Two device classes, by what they can do

A room has radiators, which only heat, and air-conditioning units,
which heat or cool on a heat pump shared with other rooms. The two
differ in kind, not only in brand: a unit's direction is not its own
to choose, a radiator's is. Within a class, nothing depends on what the
device is called: the strategies read capabilities (can it heat, cool,
is it quiet, its energy, how it gives its heat), so a gas radiator and
an electric one, or a heat pump on gas, are planned by what they are.

A third class (floor heating, a stove) has no place yet: the strategies
rank two classes, and a third would need its own rule against each.

## A band's side, not a target

The band comes from `thermidor-schedule`, heat below one side, cool
above the other, a deadband between. A radiator and a unit in one room
work to different sides, so they never fight; a device held by hand
keeps the room's others the same deadband from what it works to, for
the same reason. Cooling is always the units', at the cool side; who
heats, and how far below the heat side, is the strategy's.

## Strategies are offsets from the heat side

Each strategy gives each class an offset from the band's heat side, or
none (it does not heat): comfort leads with the gentlest, the others a
gap behind; quick, all at once; quiet, the quiet ones; cheapest, a heat
pump alone. Offsets compose: an energy rule's effects (prefer, avoid,
cap, raise) move them after the strategy, so a rule never needs to know
the strategy, nor a strategy the rules. A class alone in a room heats at
the band whatever the strategy, since there is nothing to rank it
against.

`cheapest` takes a heat pump (heats and cools on electricity) as the
cheapest, until real costs are given: pricing it needs the caller's
tariffs, and the planner has none.

## One direction a heat pump

Units on one outdoor unit cannot heat and cool at once. The direction
is voted by the rooms that can use it: a room needing heat that has
radiators steps aside on a conflict, since it has another way to be
heated and the other side has none; then the most rooms win, heat on a
tie. With no need either way, the direction it has stays. A unit
unread, or switched off by hand, does not vote: it cannot be known to want either way, nor
can it use what it would vote for. The losers are told, never silently
left out.

## Not heating is the least target

A radiator not to heat goes to its least target rather than off: a
thermostat switched off may be switched on again by its own driver
(tado's cloud does, within minutes), while a least target holds. The
least is the device's range's when it reports one, else the caller's
`least`; with neither, it is left and said rather than guessed.

## Unread is not off

A device the caller could not read is kept, with nil fields, rather
than dropped, and left as it is: what it holds now is not known, so its
nil must not be read as off and switched on, nor its nil target
rewritten. With a nil mode it gets no action, no vote, gives its class
no part, and never stands for its system's mode, the rest of the house
planned as if it were not there; a warning says it was left.

## Energy is a device's, not its class's

The strategies rank classes, but an excluded energy is checked on each
device: a room's gas radiator heats while its electric one rests at its
least target, in whichever order they are listed. Ranking by device as
well would need a rule for every pair inside a class; until a house
mixes quiet and loud devices in one class, the first that may heat
stands for the class's ranking.

## On the device's step, moved by a step or not at all

A target is written on the device's step and within its range, so it
holds what was written and reads it back unchanged; one read otherwise
was changed outside, which is what `Drifts` relies on. A target within
a step of what the device holds is left, so a translation moving a
little does not make the device move.

## Drifts are found, not judged

`Drifts` says what was changed outside and gives the band that would
hold it; what to do about it (adopt it, how long, notify whom) is the
caller's policy, so it stays there. A system's mode changing makes its
units report the other mode's setpoint, so those are not drifts of
their own.
