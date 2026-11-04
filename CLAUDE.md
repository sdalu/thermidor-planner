# thermidor-planner

How it works: README.md. Why it is shaped so: DESIGN.md. What closes a
round: CHECKLIST.md.

Gate: `bundle exec rake`

Ruby style: the `ruby` skill (4-space indentation, double quotes,
`.rubocop.yml` is its rule set).

## Traps

- Releases are the owner's: never create or push a tag, nor move
  `VERSION`, unasked. Say a release is due and which number.
- ClimatControl (~/Repos/ClimatControl, its own session's repo) is
  the one user, naming `Thermidor::Planner` directly: a renamed
  constant, field or warning breaks it (its CLI tests assert the
  warnings' text). Run its gate against this tree before it moves its
  pin.
- thermidor-schedule (~/Repos/thermidor-schedule) is the Thermidor
  session's repo: schedule work goes there, never as a copy here.
- A constant inside a nested class of a test is not found through the
  test's `include Thermidor::Planner`: name it in full
  (plan_held_test.rb's `Warmer`).
- `rubocop -a` reflows multi-line hash arguments in tests into
  something unreadable; read the diff after it.
