# frozen_string_literal: true

module Thermidor
    module Planner
        # A warning: its sentence, as text, and what it is about. kind: a
        # Symbol naming it (doc/warnings.md lists them); zone, device (a
        # device's or a system's label) and source (a heat pump's name, as
        # its units give it): those it is about, nil for none; ahead: the
        # change an early start's note is about (Ahead), nil for none.
        class Notice < String
            attr_reader :kind, :zone, :device, :source, :ahead

            ABOUT = %i[zone device source ahead].freeze

            def initialize(text, kind:, **about)
                unknown = about.keys - ABOUT
                raise ArgumentError, "unknown keywords: #{unknown.join(", ")}" \
                    unless unknown.empty?
                super(text)
                @kind   = kind
                @zone   = about[:zone]
                @device = about[:device]
                @source = about[:source]
                @ahead  = about[:ahead]
            end
        end
    end
end
