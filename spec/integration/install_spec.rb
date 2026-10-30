# frozen_string_literal: true

RSpec.describe "bin/rails g agent_harness:install" do
  it "creates the three files in the dummy app, and the config loads without warnings" do
    with_dummy_app_copy do |app_root|
      output, status = run_in(app_root, "bin/rails g agent_harness:install", env: {"RAILS_ENV" => "development"})

      expect(status).to be_success, output
      %w[config/agent_harness.yml AGENTS.md CLAUDE.md .claude/skills/rails-review/SKILL.md].each do |file|
        expect(File).to exist(File.join(app_root, file)), "expected #{file}\n#{output}"
      end
      expect(output).to include("Rails version:  #{Rails::VERSION::STRING}") if defined?(Rails::VERSION)
      expect(File.read(File.join(app_root, "AGENTS.md"))).to include("# Agent instructions", "- Database: SQLite")
      expect(File.read(File.join(app_root, "CLAUDE.md"))).to include("@AGENTS.md")

      script = <<~RUBY
        require "rails_agent_harness"
        config = RailsAgentHarness::Configuration.load(ARGV[0])
        print config.to_h == RailsAgentHarness::Configuration::DEFAULTS.merge("checks" => config.to_h["checks"])
      RUBY
      lib = File.expand_path("../../lib", __dir__)
      stdout, stderr, status = Open3.capture3("ruby", "-I", lib, "-e", script, app_root)
      expect(status).to be_success, stderr
      expect(stderr).to be_empty
      expect(stdout).to eq("true")
    end
  end
end
