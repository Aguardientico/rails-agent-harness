# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "8.0")
gem "rails", "~> #{rails_version}.0"
# Rails 7.1 only supports sqlite3 1.x; Rails 8.0 requires >= 2.1.
gem "sqlite3", (rails_version == "7.1") ? "~> 1.4" : ">= 2.1"

gem "rake"
gem "rspec", "~> 3.13"
gem "standard"
