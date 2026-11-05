# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The bands and strategies planned from: the sibling gem, pinned at a
# commit (no tag yet), the one ClimatControl pins.
gem "thermidor-schedule", github: "sdalu/thermidor-schedule",
                          ref: "c855195f5845a18cd37cfab4baa51231b260aeca"

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.2"
    gem "rubocop", "~> 1.90"
end
