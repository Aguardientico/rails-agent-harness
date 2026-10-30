# frozen_string_literal: true

require_relative "lib/rails_agent_harness/version"

Gem::Specification.new do |spec|
  spec.name = "rails_agent_harness"
  spec.version = RailsAgentHarness::VERSION
  spec.authors = ["Gustavo Gonzalez"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.summary = "Make AI coding agents (Claude Code, Codex, Cursor) safe and productive in Rails apps."
  spec.description = "Install generator, fast checker and guards that make AI coding agents " \
    "(Claude Code, Codex, Cursor) safe and productive in Rails apps."
  spec.homepage = "https://github.com/Aguardientico/rails-agent-harness"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.1", "< 9"
end
