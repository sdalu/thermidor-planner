# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The bands and strategies planned from: the sibling gem, at the release
# tag ClimatControl pins (or the commit, between releases).
gem "thermidor-schedule", github: "sdalu/thermidor-schedule",
                          tag: "v0.2.0"

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.2"
    gem "rubocop", "~> 1.90"
end
