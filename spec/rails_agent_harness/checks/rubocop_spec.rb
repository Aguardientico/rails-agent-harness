# frozen_string_literal: true

require "rails_agent_harness/checks"

RSpec.describe RailsAgentHarness::Checks::Rubocop do
  around do |example|
    Dir.mktmpdir("agent_harness_rubocop") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  let(:runner) { AgentCheckHelper::FakeRunner.new }
  let(:profile) { build_profile }
  let(:config) { load_config(root) }

  def check(files, runner: self.runner, profile: self.profile, config: self.config)
    described_class.new(root: root, config: config, profile: profile, files: files, runner: runner).call
  end

  it "passes when RuboCop exits 0" do
    result = check(%w[app/models/post.rb])

    expect(result.status).to eq(:pass)
    expect(runner.calls).to eq([%w[bundle exec rubocop --format emacs --force-exclusion --no-color app/models/post.rb]])
  end

  it "only checks Ruby files" do
    check(%w[app/models/post.rb app/views/posts/index.html.erb Gemfile lib/tasks/x.rake config.ru x.gemspec Rakefile README.md])

    expect(runner.calls.first.last(6)).to eq(%w[app/models/post.rb Gemfile lib/tasks/x.rake config.ru x.gemspec Rakefile])
  end

  it "fails with root-relative offense lines" do
    output = <<~OUT
      #{root}/app/models/post.rb:3:5: C: [Correctable] Style/StringLiterals: Prefer double-quoted strings.
      #{root}/app/models/post.rb:4:1: W: Lint/UselessAssignment: Useless assignment to variable - x.
    OUT
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output, exit_status: 1))

    expect(result.status).to eq(:fail)
    expect(result.summary).to eq("2 offenses")
    expect(result.details).to eq([
      "app/models/post.rb:3:5: C: [Correctable] Style/StringLiterals: Prefer double-quoted strings.",
      "app/models/post.rb:4:1: W: Lint/UselessAssignment: Useless assignment to variable - x."
    ])
  end

  it "reports the output tail when RuboCop fails without offenses" do
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: "Error: bad config\n", exit_status: 2))

    expect(result.status).to eq(:fail)
    expect(result.summary).to eq("exit status 2")
    expect(result.details).to eq(["Error: bad config"])
  end

  describe "skipping" do
    it "skips when disabled in config" do
      result = check(%w[app/models/post.rb], config: load_config(root, "checks:\n  rubocop:\n    enabled: false\n"))

      expect(result.status).to eq(:skip)
      expect(runner.calls).to be_empty
    end

    it "skips without changed Ruby files" do
      expect(check(%w[README.md]).summary).to eq("no changed Ruby files")
    end

    it "skips when RuboCop isn't detected and no command is configured" do
      result = check(%w[app/models/post.rb], profile: build_profile(rubocop: false))

      expect(result).to have_attributes(status: :skip, summary: "RuboCop not detected")
    end

    it "runs a configured command even when RuboCop isn't detected" do
      config = load_config(root, "checks:\n  rubocop:\n    command: bin/lint --strict\n")
      check(%w[app/models/post.rb], profile: build_profile(rubocop: false), config: config)

      expect(runner.calls.first.first(2)).to eq(%w[bin/lint --strict])
    end
  end

  describe "command detection" do
    it "prefers an executable bin/rubocop" do
      touch(root, "bin/rubocop", executable: true)
      check(%w[app/models/post.rb])

      expect(runner.calls.first.first).to eq("bin/rubocop")
    end

    it "uses standardrb for Standard apps without a .rubocop.yml" do
      check(%w[app/models/post.rb], profile: build_profile(standard: true))

      expect(runner.calls.first.first(3)).to eq(%w[bundle exec standardrb])
    end

    it "uses rubocop for Standard apps with a .rubocop.yml" do
      touch(root, ".rubocop.yml")
      check(%w[app/models/post.rb], profile: build_profile(standard: true))

      expect(runner.calls.first.first(3)).to eq(%w[bundle exec rubocop])
    end
  end
end
