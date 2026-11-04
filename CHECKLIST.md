# Closing a round on thermidor-planner

## Gates

- [ ] `bundle exec rake` passes: tests (README's example among them),
  then RuboCop.
- [ ] `gh run list -R sdalu/thermidor-planner -L 1` shows the pushed
  commit's gate passed on GitHub.
- [ ] Does ClimatControl's gate still pass against this tree (a scratch
  clone of it, its Gemfile pointed at the local path)? It is the one
  user, and pins a commit or a tag.

## Documents

- [ ] `README.md`: do the types' table, the arguments of `Plan`, the
  strategies and the shortfalls still match the code?
- [ ] `DESIGN.md`: did this round change a reason it gives, or make a
  choice it should record?

## Release

- [ ] Does `Thermidor::Planner::VERSION` in
  `lib/thermidor/planner/version.rb` move with this round? It is the
  one place the release number is written. Its user (ClimatControl)
  pins a commit or a tag, which the owner makes: propose the number, do
  not tag.
- [ ] Did `thermidor-schedule`'s pin in the Gemfile move? Keep it the
  commit ClimatControl pins, and the gemspec's `~>` able to take it.
