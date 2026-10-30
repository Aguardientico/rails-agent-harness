# frozen_string_literal: true

require "json"
require "rails_agent_harness/checks"

RSpec.describe RailsAgentHarness::Checks::Brakeman do
  around do |example|
    Dir.mktmpdir("agent_harness_brakeman") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  let(:runner) { AgentCheckHelper::FakeRunner.new(output: JSON.generate("warnings" => [])) }
  let(:config) { load_config(root) }

  def check(files = %w[app/models/post.rb], runner: self.runner, profile: build_profile, config: self.config)
    described_class.new(root: root, config: config, profile: profile, files: files, runner: runner).call
  end

  def warning(confidence, file: "app/controllers/posts_controller.rb", line: 12)
    {"warning_type" => "SQL Injection", "message" => "Possible SQL injection", "file" => file, "line" => line, "confidence" => confidence}
  end

  it "runs Brakeman quietly with JSON output and passes without warnings" do
    expect(check.status).to eq(:pass)
    expect(runner.calls).to eq([%w[bundle exec brakeman --quiet --no-pager --format json --no-exit-on-warn --no-exit-on-error]])
  end

  it "fails on High and Medium confidence warnings, ignoring Weak ones" do
    output = JSON.generate("warnings" => [warning("Weak", line: 3), warning("Medium", line: 20), warning("High")])
    result = check(runner: AgentCheckHelper::FakeRunner.new(output: output))

    expect(result).to have_attributes(status: :fail, summary: "2 warnings")
    expect(result.details).to eq([
      "app/controllers/posts_controller.rb:12 [High] SQL Injection: Possible SQL injection",
      "app/controllers/posts_controller.rb:20 [Medium] SQL Injection: Possible SQL injection"
    ])
  end

  it "parses only stdout, so braces in stderr warnings don't break it" do
    runner = AgentCheckHelper::FakeRunner.new(output: JSON.generate("warnings" => []), stderr: "warning: {a: 1} is deprecated }\n")

    expect(check(runner: runner).status).to eq(:pass)
    expect(runner.options).to eq([{separate_stderr: true}])
  end

  # Brakeman's real error shape: the file is in the message, `location` is its own backtrace.
  def parse_error(file)
    {"error" => "#{file}:3 :: parse error on value \"end\" (kEND) While processing #{file}",
     "location" => "/gems/ruby_parser-3.22.0/lib/ruby_parser.rb:41:in `process'"}
  end

  it "lists files Brakeman couldn't parse next to the warnings" do
    output = JSON.generate("warnings" => [warning("High")], "errors" => [parse_error("app/models/x.rb")])
    result = check(runner: AgentCheckHelper::FakeRunner.new(output: output))

    expect(result).to have_attributes(status: :fail, summary: "1 warning")
    expect(result.details).to eq([
      "app/controllers/posts_controller.rb:12 [High] SQL Injection: Possible SQL injection",
      "brakeman error: app/models/x.rb:3 :: parse error on value \"end\" (kEND) While processing app/models/x.rb"
    ])
  end

  it "fails when a changed file couldn't be scanned" do
    output = JSON.generate("warnings" => [], "errors" => [parse_error("app/models/post.rb")])
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output))

    expect(result).to have_attributes(status: :fail, summary: "1 changed file not scanned")
    expect(result.details.first).to start_with("brakeman error: app/models/post.rb:3 :: parse error")
  end

  it "passes when only an unchanged file couldn't be scanned" do
    output = JSON.generate("warnings" => [], "errors" => [parse_error("app/models/legacy.rb")])

    expect(check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output)).status).to eq(:pass)
  end

  it "fails when Brakeman exits non-zero even with valid JSON" do
    result = check(runner: AgentCheckHelper::FakeRunner.new(output: JSON.generate("warnings" => []), exit_status: 1))

    expect(result).to have_attributes(status: :fail, summary: "brakeman exited with status 1")
  end

  it "matches parse errors to changed files by whole path" do
    output = JSON.generate("warnings" => [], "errors" => [parse_error("app/lib/a.rb")])

    expect(check(%w[lib/a.rb], runner: AgentCheckHelper::FakeRunner.new(output: output)).status).to eq(:pass)
    expect(check(%w[app/lib/a.rb], runner: AgentCheckHelper::FakeRunner.new(output: output)).status).to eq(:fail)

    absolute = JSON.generate("warnings" => [], "errors" => [{"error" => "#{root}/app/models/post.rb:3 :: parse error"}])
    expect(check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: absolute)).status).to eq(:fail)
  end

  it "passes with only Weak warnings" do
    expect(check(runner: AgentCheckHelper::FakeRunner.new(output: JSON.generate("warnings" => [warning("Weak")]))).status).to eq(:pass)
  end

  it "fails when the output isn't JSON" do
    result = check(runner: AgentCheckHelper::FakeRunner.new(output: "brakeman: command not found\n", exit_status: 127))

    expect(result).to have_attributes(status: :fail, summary: "could not read Brakeman's JSON output (exit status 127)")
    expect(result.details).to eq(["brakeman: command not found"])
  end

  it "prefers an executable bin/brakeman and honors a configured command" do
    touch(root, "bin/brakeman", executable: true)
    check
    expect(runner.calls.last.first).to eq("bin/brakeman")

    check(config: load_config(root, "checks:\n  brakeman:\n    command: bundle exec brakeman -c config/brakeman.yml\n"))
    expect(runner.calls.last.first(5)).to eq(%w[bundle exec brakeman -c config/brakeman.yml])
  end

  describe "skipping" do
    it "skips when disabled" do
      result = check(config: load_config(root, "checks:\n  brakeman:\n    enabled: false\n"))

      expect(result.status).to eq(:skip)
      expect(runner.calls).to be_empty
    end

    it "skips when Brakeman isn't detected and no command is configured" do
      expect(check(profile: build_profile(brakeman: false)).summary).to eq("Brakeman not detected")
    end

    it "skips when nothing under app/, config/ or lib/ (or Gemfile.lock) changed" do
      expect(check(%w[spec/models/post_spec.rb README.md]).summary).to eq("no changed files under app/, config/ or lib/")
      expect(check(%w[Gemfile.lock]).status).to eq(:pass)
      expect(check(%w[config/routes.rb]).status).to eq(:pass)
      expect(check(%w[lib/tasks/x.rake]).status).to eq(:pass)
    end
  end
end
