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
fills in (`label`, `system`, `least`, `step`), and a translation is
asked of the device itself, which the caller maps to its own names.

## Two device classes, by what they can do

A room has radiators, which only heat, and air-conditioning units,
which heat or cool on a heat pump shared with other rooms. The two
differ in kind, not only in brand: a unit's direction is not its own
to choose, a radiator's is. Nothing depends on what a device is
called: the strategies read each device's capabilities (can it heat,
cool, is it quiet, its energy, how it gives its heat), so a gas radiator
and an electric one, or a heat pump on gas, are planned by what they
are.

A third class (floor heating, a stove) has no place yet: its devices
would rank like the others, but its direction and its least are its
own, and would need their own rules.

## A band's side, not a target

The band comes from `thermidor-schedule`, heat below one side, cool
above the other, a deadband between. A radiator and a unit in one room
work to different sides, so they never fight; a device held by hand
keeps the room's others the same deadband from what it works to, for
the same reason. Cooling is always the units', at the cool side; who
heats, and how far below the heat side, is the strategy's.

## Strategies are offsets from the heat side, device by device

Each strategy gives each device an offset from the band's heat side, or
none (it does not heat): comfort leads with the gentlest, the others a
gap behind; quick, all at once; quiet, the quiet ones; cheapest, the
heat pumps. Offsets compose: an energy rule's effects (prefer, avoid,
cap, raise) move them after the strategy, so a rule never needs to know
the strategy, nor a strategy the rules.

The ranking is a device's, not its class's: a quiet and a loud radiator
in one room are two things to rank, and judging the class by one of
them made the result depend on which was listed first (under quiet,
both heated or neither). Ranking each device removes listing order from
every rule; what stays class-bound is said where it holds (cheapest
with neither costs nor a heat pump, a device without caps).

Devices all of one kind in a room have nothing to be ranked against, so
they heat at the band whatever the strategy: two identical radiators
under quiet heat, loud or not, as a class alone always did. "Alone"
counts kinds, not devices, for that reason: counting devices would
leave two loud radiators cold under quiet where one would heat.
Equally gentle devices lead together under comfort: there is nothing
to choose between them, and a tiebreak would bring order back.

`cheapest` ranks by what a kWh of heat costs from each device, which
the caller gives (`room.costs`): pricing needs its tariffs and each
device's efficiency at the weather, and the planner has neither. It
uses them only when every device taking part has one, since a device
without a cost cannot be put above or below the others; then it falls
back on a guess, a heat pump (heats and cools on electricity) taken as
the cheapest, and with none the radiators.

A translation is asked of each device, not of its class: two radiators
in one room may sit by sensors that read the room differently, and only
the caller knows which share one.

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

## A device takes part on its own

Whether a device heats at all is its own: read, able to heat, on an
energy not excluded now, and able to go as low as the band. A room's
gas radiator heats while its electric one rests at its least target; a
unit whose least setpoint is above an away band is switched off rather
than set to that least, above the band. A room votes for a heat pump
only by a unit on it that may heat the room.

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
