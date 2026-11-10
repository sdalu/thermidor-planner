# frozen_string_literal: true

module Thermidor
    module Planner
        # What a warm-up's heat costs, for WarmUpCosts: a set's cost of a
        # kWh of heat in a period, from the period's costs by label.
        module WarmUpPrices
            # A device with no cost in a period.
            Uncosted = Data.define(:label, :minute)

            private

            def price(name, period)
                (@prices ||= {})[[name, period]] ||=
                    priced(labels(name, period), period)
            end

            # A set's cost of a kWh of heat: one class's mean; two, by
            # each class's share of the heat (its Rise#base).
            def priced(found, period)
                shares = classes(found).transform_values do |labels|
                    mean_cost(labels, period)
                end
                bases = shares.keys.to_h { [it, rates_for[it]&.base] }
                return mean(shares.values) if
                    shares.size < 2 || bases.value?(nil)
                weighted(shares, bases)
            end

            def weighted(shares, bases)
                shares.sum { |key, each| bases[key] * each } / bases.values.sum
            end

            def mean(values) = values.sum.fdiv([values.size, 1].max)

            def classes(found)
                found.group_by { @radiators.include?(it) ? :radiators : :units }
            end

            def mean_cost(found, period)
                costs = found.map do |label|
                    period.costs[label] ||
                        throw(:uncosted, Uncosted.new(label:,
                                                      minute: period.minutes))
                end
                costs.sum.fdiv(costs.size)
            end

            def period_at(minute)
                periods.reverse.find { it.minutes <= minute } || periods.first
            end
        end
    end
end
