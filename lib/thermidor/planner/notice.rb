# frozen_string_literal: true

module Thermidor
    module Planner
        # A warning: its sentence, as text, and what it is about. kind: a
        # Symbol naming it (README lists them); zone, device (a device's
        # or a system's label) and source (a heat pump's name, as its
        # units give it): those it is about, nil for none.
        class Notice < String
            attr_reader :kind, :zone, :device, :source

            def initialize(text, kind:, zone: nil, device: nil, source: nil)
                super(text)
                @kind   = kind
                @zone   = zone
                @device = device
                @source = source
            end
        end
    end
end
