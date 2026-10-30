# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# RAILS_VERSION picks the Rails release to test against ("8.1", ...) or "main".
# The gemspec allows railties < 9, so the allowed-to-fail CI job against main
# will start failing once main moves to 9.0.0.alpha; that is the cue to widen it.
rails_version = ENV.fetch("RAILS_VERSION", "8.1")
if rails_version == "main"
  gem "rails", github: "rails/rails", branch: "main"
else
  gem "rails", "~> #{rails_version}.0"
end
gem "sqlite3", ">= 2.1"

gem "rake"
gem "rspec", "~> 3.13"
gem "standard"
