# frozen_string_literal: true

require "thermidor/schedule"

require_relative "planner/version"
require_relative "planner/effects"

module Thermidor
    # From what the schedule decided for each room and what its devices
    # report, what to tell each device: thermostats on radiators, which
    # only heat, and air-conditioning units, whose units on one heat pump
    # (a source) must share one direction. It decides only: reading the
    # devices and writing to them is the caller's.
    #
    # A device's caps say what it can do, read by duck typing: heat and
    # cool (true or false), quiet (true or false), energy (a name such as
    # "gas" or "electricity") and propagation (how it gives its heat,
    # most of it first: "radiation", "conduction", "convection",
    # "forced").
    module Planner
        class Error < StandardError; end

        # A thermostat on a radiator: mode :off or :heat (nil: unread),
        # its target, the targets it takes (range, nil: any) on its step.
        # label: its name in actions and drifts (tado:SERIAL, say); least:
        # the target that stands for not heating where the range says
        # none, nil when there is none.
        Radiator = Data.define(:ref, :label, :caps, :temperature, :mode,
                               :target, :range, :step, :least) do
            def initialize(least: nil, **) = super
        end

        # An air-conditioning unit: on or off, a mode (:heat, :cool, :aux
        # heating with a backup heater, :fan, :dry, :auto, :stop; nil:
        # unread) and the setpoint of that mode. system: the label of the
        # units sharing its mode, which is set through its master unit;
        # source: the heat pump its system runs on, whose direction every
        # unit on it shares. range: its setpoints now, in the mode it is
        # in; ranges: by mode (:heat, :cool), those it gives.
        Aircon = Data.define(:ref, :label, :caps, :system, :source, :master,
                             :temperature, :on, :mode, :setpoint, :range,
                             :ranges, :step) do
            def initialize(ranges: {}, **) = super

            # The setpoints it takes in direction.
            def range_in(direction) = ranges.to_h.fetch(direction, range)
        end

        # A room: the band and strategy decided, and its devices.
        # excluded: the energies its devices may not heat on now.
        # measured: its °C from a reference of its own, nil when it has
        # none; location: where that reference is, for a translation, nil
        # for none; held: its devices switched outside the planner and
        # held so (Radiator or Aircon), left out of the plan but watched;
        # effects: what its energy rules do besides excluding (Effects);
        # costs: what a kWh of heat costs from each device now, by label,
        # in any one unit, for cheapest (none: a heat pump is taken as
        # the cheapest); outside: the outside °C now, nil unknown, for the
        # pump's mild-weather settings (PumpSettings).
        ROOM_DEFAULTS = { excluded: [], measured: nil, location: nil,
                          held: [], effects: Effects.none,
                          costs: {}, outside: nil }.freeze

        Room = Data.define(:zone, :band, :strategy, :radiators, :aircons,
                           :excluded, :measured, :location, :held,
                           :effects, :costs, :outside) do
            def initialize(**) = super(**ROOM_DEFAULTS, **)

            # Every device, held or not.
            def devices = radiators + aircons + held

            # The room's temperature: the measured one, else what its
            # devices read, averaged; nil without either.
            def temperature = measured || devices_temperature

            def devices_temperature
                readings = (radiators + aircons).filter_map(&:temperature)
                readings.sum.fdiv(readings.size).round(1) unless readings.empty?
            end

            # The temperature as said: "(devices)" after it when none was
            # measured; nil without one.
            def reading
                return measured.round(1).to_s if measured
                devices_temperature&.then { "#{it} (devices)" }
            end

            # :heat below the band (lifted by a raise on the energy of one
            # of its devices that may heat), :cool above it, else nil; nil
            # without a band.
            def need
                now = band && temperature or return
                return :heat if band.heat && now < band.heat + lift
                :cool if band.cool && now > band.cool
            end

            # A raise's lift, by the devices that may heat: read, able to,
            # on an energy not excluded now.
            def lift
                taking = (radiators + aircons).select do |device|
                    device.mode && Roles.heats?(device, excluded)
                end
                effects.lift(taking.map { it.caps.energy }.uniq)
            end
        end

        # One change for a device: setting :mode, :power, :target or
        # :setpoint, from what it is (nil: unknown) to what it should be;
        # offset: what a target or setpoint adds to the band's for the
        # device's own sensor (a translation's), nil for none.
        Action = Data.define(:zone, :device, :setting, :from, :to, :offset,
                             :why) do
            def initialize(offset: nil, **) = super
        end

        # actions: Action, ...; warnings: Notice, ..., a translation's
        # notes after them as it gave them.
        Result = Data.define(:actions, :warnings)
    end
end

require_relative "planner/notice"
require_relative "planner/translation"
require_relative "planner/pump_settings"
require_relative "planner/strategy"
require_relative "planner/roles"
require_relative "planner/source"
require_relative "planner/actions"
require_relative "planner/fit"
require_relative "planner/device_plan"
require_relative "planner/pump_cycle"
require_relative "planner/pump_notices"
require_relative "planner/pump_plan"
require_relative "planner/held_devices"
require_relative "planner/plan"
require_relative "planner/drifts"
