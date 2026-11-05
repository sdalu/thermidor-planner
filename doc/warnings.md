# Warnings

What [the planner](README.md) could not do, said in `Result#warnings`.
Each is a `Notice`: a `String`, the sentence, which also says what it
is about, so a caller choosing which to show or pass on reads fields
rather than parsing the words.

| `Notice` | What it is                                             |
| :------- | :----------------------------------------------------- |
| `kind`   | a Symbol naming it                                     |
| `zone`   | the room's zone it is about, nil for none              |
| `device` | a device's label or a system's, nil for none           |
| `source` | a heat pump's name, as its units give it, nil for none |

The translation's `notes` come after the notices, as it gave them: they
are its own, not `Notice`s.

## The kinds

| `kind`              | Said of                                                      | About                |
| :------------------ | :----------------------------------------------------------- | :------------------- |
| `:unread`           | a device not read, left as it is                             | zone, device         |
| `:no_least`         | a radiator not to heat with no least target, left            | zone, device         |
| `:unheated`         | a room needing heat that none of its devices heat, with why  | zone                 |
| `:unserved`         | a room needing what its heat pump does not give              | zone, source         |
| `:held_against`     | a unit held by hand the other way from its heat pump         | zone, device, source |
| `:left_in_auto`     | a system left in auto, its heat pump with no direction       | device, source       |
| `:past_band`        | a device held by hand working past the band                  | zone, device         |
| `:kept`             | a heat pump's units kept as they are for its least time      | source               |
| `:unknown_strategy` | a room's strategy with no rule nor alias, planned as comfort | zone                 |

## The sentences

In capitals what each one fills in; °C with one decimal.

| `kind`              | Sentence                                                                |
| :------------------ | :---------------------------------------------------------------------- |
| `:unread`           | `ZONE: LABEL not read: left as it is`                                   |
| `:no_least`         | `ZONE: LABEL has no least target: left as it is`                        |
| `:unheated`         | `ZONE: needs heat, but WHY`                                             |
| `:unserved`         | `ZONE: needs NEED, but SOURCE DIRECTION`                                |
| `:held_against`     | `ZONE: LABEL held DOING, the heat pump goes DOING`                      |
| `:left_in_auto`     | `SYSTEM: left in auto: the heat pump SOURCE has no direction now`       |
| `:past_band`        | `ZONE: LABEL left on, heating to T °C, above the band's cool side T °C` |
|                     | `ZONE: LABEL left on, cooling to T °C, below the band's heat side T °C` |
| `:kept`             | `SOURCE: kept running: started N min ago, at least M`                   |
|                     | `SOURCE: kept stopped: stopped N min ago, at least M`                   |
| `:unknown_strategy` | `ZONE: strategy NAME unknown, planned as comfort`                       |

- WHY, the first that holds: `no device can heat it` (none read can);
  `ENERGY is excluded now` (the room's excluded energies, joined with
  `, `); `no device heats as low as T °C` (the band's heat side).
- NEED is `heat` or `cool`; DIRECTION `heat`, `cool`, or `stays off`.
- DOING is `heating` or `cooling`.
- N is the minutes since the heat pump switched, rounded; M the least
  time set, `min_on` or `min_off`.

A room needing heat whose devices are all unread or held is not said
`:unheated`: an unread one is said as such, and one held is the
caller's.

As plans give them, from rooms built to raise each one:

```text
u: valve:VR not read: left as it is
u: valve:N has no least target: left as it is
e: needs heat, but gas is excluded now
f: needs heat, but no device heats as low as 5.0 °C
g: needs heat, but no device can heat it
office: needs cool, but pump heat
a: needs heat, but pump stays off
h: unit:h held cooling, the heat pump goes heating
system:1: left in auto: the heat pump pump has no direction now
a: valve:VA left on, heating to 26.5 °C, above the band's cool side 26.0 °C
pump: kept running: started 5 min ago, at least 15
pump: kept stopped: stopped 3 min ago, at least 10
office: strategy eco unknown, planned as comfort
```
