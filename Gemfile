# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The bands and strategies planned from: the sibling gem, pinned at a
# commit (no tag yet), the one ClimatControl pins.
gem "thermidor-schedule", github: "sdalu/thermidor-schedule",
                          ref: "bc82c6d4d1e2791c9dab8d567c980aa39911952e"

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.2"
    gem "rubocop", "~> 1.90"
end
