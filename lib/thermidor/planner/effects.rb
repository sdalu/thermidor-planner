# frozen_string_literal: true

module Thermidor
    module Planner
        # What a room's energy rules, holding now, do to its device
        # classes besides excluding them, by energy:
        # preferred lead; avoided back up, never lead; caps ({ energy =>
        # °C }) heat at most that far under the band's heat side; raises
        # ({ energy => °C }) heat that far over it, storing heat while it
        # is cheap.
        Effects = Data.define(:preferred, :avoided, :caps, :raises) do
            def self.none
                new(preferred: [], avoided: [], caps: {}, raises: {})
            end

            # From verdicts on a room's rules: anything answering
            # preferred, avoided, caps and raises.
            def self.of(verdicts)
                new(preferred: verdicts.preferred, avoided: verdicts.avoided,
                    caps: verdicts.caps, raises: verdicts.raises)
            end

            def none? = self == Effects.none

            # offsets ({ role => offset from the band's heat side, or nil })
            # as the effects change them; energies: { role => energy };
            # gap: a backup's distance under the lead (comfort's).
            def apply(offsets, energies, gap)
                return offsets if none?
                led = lead(offsets, energies, gap)
                led.to_h do |role, offset|
                    [role, bound(offset, energies.fetch(role))]
                end
            end

            # The most a room's heat side is lifted by a raise on one of
            # these energies.
            def lift(energies)
                raises.slice(*energies).values.max.to_f
            end

            private

            # The preferred lead, the others leading back up a gap
            # behind; an avoided lead steps back, another taking the lead.
            def lead(offsets, energies, gap)
                preferred = offsets.keys.select do |role|
                    self.preferred.include?(energies[role])
                end
                offsets = promote(offsets, preferred, -gap) if preferred.any?
                step_back(offsets, energies, gap)
            end

            def promote(offsets, leads, behind)
                offsets.to_h do |role, offset|
                    next [role, 0.0] if leads.include?(role)
                    [role, offset == 0.0 ? behind : offset]
                end
            end

            # Avoided leads back up; when none is left leading, the first
            # class not avoided leads. Every class avoided: unchanged.
            def step_back(offsets, energies, gap)
                avoided, others = offsets.keys.partition do |role|
                    self.avoided.include?(energies[role])
                end
                return offsets if avoided.empty? || others.empty?
                stepped = behind(offsets, avoided, gap)
                return stepped if others.any? { stepped[it] == 0.0 }
                stepped.merge(others.first => 0.0)
            end

            # The roles taking part a gap behind the lead.
            def behind(offsets, roles, gap)
                offsets.to_h do |role, offset|
                    [role, roles.include?(role) && offset ? -gap : offset]
                end
            end

            # A raise lifts the class to it, whatever its part; a cap
            # limits it.
            def bound(offset, energy)
                offset = raises[energy] if raises.key?(energy)
                return offset unless offset && caps.key?(energy)
                [offset, -caps[energy]].min
            end
        end
    end
end
