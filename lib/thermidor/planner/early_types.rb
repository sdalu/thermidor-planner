# frozen_string_literal: true

module Thermidor
    module Planner
        # How early start runs in a room (design/early-start.md). lead: the
        # most minutes a change is started ahead; reach: how far inside
        # its side (°C) a room counts as in the band, aimed at for the
        # change's time; warmup: the strategy every warm-up runs, :own for
        # the change's own; hurry: whether a warm-up its strategy cannot
        # bring in time runs quick instead; fallback: the minutes ahead a
        # change starts with no rate for its devices (nil: it does not).
        EarlyStartSettings = Data.define(:lead, :reach, :warmup, :hurry,
                                         :fallback) do
            def initialize(lead: 180, reach: 0.2, warmup: :own,
                           hurry: false, fallback: nil)
                raise ArgumentError, "lead #{lead} is not positive" unless
                    lead.positive?
                raise ArgumentError, "negative reach #{reach}" if
                    reach.negative?
                raise ArgumentError, "negative fallback #{fallback}" if
                    fallback&.negative?
                raise ArgumentError, "hurry #{hurry.inspect} is no boolean" \
                    unless [true, false].include?(hurry)
                super(lead:, reach:, warmup: warmup.to_sym, hurry:, fallback:)
            end
        end

        # A change ahead, as the caller found it: minutes until it, the
        # band (Schedule::Setpoint) and strategy it brings; started: the
        # strategy of the warm-up the caller holds for it already, nil when
        # none: the latch, and the strategy chosen, kept.
        Ahead = Data.define(:minutes, :band, :strategy, :started) do
            def initialize(minutes:, band:, strategy:, started: nil)
                raise ArgumentError, "negative minutes #{minutes}" if
                    minutes.negative?
                super
            end
        end

        # How fast a room's temperature moves with a set of devices at full
        # call: base, °C/h with the outside as warm as the room; loss, 1/h,
        # what each °C of inside-outside gap takes off it (cooling: adds);
        # delay, minutes before the room starts to move; gap, the mean
        # inside-outside gap it was learned over, for an outside not known.
        Rise = Data.define(:base, :loss, :delay, :gap) do
            def initialize(base:, loss: 0.0, delay: 0.0, gap: nil)
                raise ArgumentError, "base #{base} is not positive" unless
                    base.positive?
                raise ArgumentError, "negative loss #{loss}" if loss.negative?
                raise ArgumentError, "negative delay #{delay}" if
                    delay.negative?
                super
            end
        end

        # From minutes from now until the next Period: what a kWh of heat
        # costs from each device, by label (as Room#costs), and the
        # energies excluded (as Room#excluded).
        Period = Data.define(:minutes, :costs, :excluded) do
            def initialize(minutes:, costs: {}, excluded: []) = super
        end

        # What EarlyStart gives a room: band and strategy to hold now (the
        # room's own when nothing starts); ahead: the Ahead it starts for,
        # nil when none; minutes: what reaching it takes from now, nil
        # without a rate; notes: Notices, said whether or not it starts.
        Start = Data.define(:band, :strategy, :ahead, :minutes, :notes)

        # A room's temperature moving at dT/dt = push − loss·(T − outside),
        # in °C and hours: push, its devices' base (heating +, cooling −,
        # none 0).
        Trend = Data.define(:push, :loss, :outside) do
            # The temperature hours after being t.
            def after(t, hours)
                return t + (push * hours) if loss.zero?
                settle + ((t - settle) * Math.exp(-loss * hours))
            end

            # Hours from t to aim, nil when it never gets there.
            def hours_to(t, aim)
                return 0.0 if t == aim
                return steady_hours(t, aim) if loss.zero?
                ratio = (t - settle) / (aim - settle)
                Math.log(ratio) / loss if ratio > 1
            end

            # Without loss, at push alone.
            def steady_hours(t, aim)
                hours = push.zero? ? -1 : (aim - t) / push
                hours if hours.positive?
            end

            def settle = outside + (push / loss)
        end
    end
end
