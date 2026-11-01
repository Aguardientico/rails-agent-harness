# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# RAILS_VERSION picks the Rails release to test against ("main" or "8.1", ...).
# The gemspec allows railties < 9, so the CI job against main will start failing
# once main moves to 9.0.0.alpha; that is the cue to widen it.
rails_version = ENV.fetch("RAILS_VERSION", "main")
if rails_version == "main"
  gem "rails", github: "rails/rails", branch: "main"
else
  gem "rails", "~> #{rails_version}.0"
end
gem "sqlite3", ">= 2.10"

gem "brakeman", "~> 8.1", require: false
gem "rake", "~> 13.4"
gem "rspec", "~> 3.13", ">= 3.13.2"
gem "standard", "~> 1.57"
