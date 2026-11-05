# frozen_string_literal: true

module Thermidor
    module Planner
        # A device's target or setpoint as it can hold it: on its step,
        # within its range; and whether what it holds is near enough to
        # what is wanted to be left alone.
        module Fit
            module_function

            # On step, within range (nil, or an open end: no bound).
            def fit(celsius, step, range)
                fitted = ((celsius / step).round * step).round(1)
                range ? fitted.clamp(range) : fitted
            end

            # Whether value (nil: unknown) stays: within one step of what
            # is wanted, so an offset moving a little does not make the
            # device move, or already where wanted lands.
            def kept?(value, wanted, step, range)
                return false unless value
                (value - wanted).abs < step - 0.01 ||
                    (value - fit(wanted, step, range)).abs < 0.05
            end
        end
    end
end
