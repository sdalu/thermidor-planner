# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The bands and strategies planned from: the sibling gem, pinned at a
# commit (no tag yet), the one ClimatControl pins.
gem "thermidor-schedule", github: "sdalu/thermidor-schedule",
                          ref: "2b55a0e7f0c0c7f15cb83ae923d633673152f852"

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.2"
    gem "rubocop", "~> 1.90"
end
