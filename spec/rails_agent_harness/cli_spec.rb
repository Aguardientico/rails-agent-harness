# frozen_string_literal: true

require "json"
require "rails_agent_harness/cli"

RSpec.describe RailsAgentHarness::CLI do
  around do |example|
    with_git_repo("app/models/post.rb" => "class Post; end\n") do |root|
      @root = root
      example.run
    end
  end

  attr_reader :root, :stdout, :stderr

  # Runs the CLI with a fake check registry so no real tools run.
  def run_cli(*argv, stdin: "", env: {"CLAUDE_PROJECT_DIR" => root})
    @stdout = StringIO.new
    @stderr = StringIO.new
    described_class.start(argv, stdin: StringIO.new(stdin), stdout: @stdout, stderr: @stderr, env: env)
  end

  def fake_check(name, status, details: [])
    calls = (@calls ||= [])
    Class.new(RailsAgentHarness::Checks::Base) do
      check_name name
      define_method(:call) do
        calls << [name, files]
        (status == :fail) ? failure("1 problem", details) : pass
      end
    end
  end

  def use_checks(*checks)
    allow(RailsAgentHarness::Checks).to receive(:registry).and_return(checks)
  end

  let(:calls) { @calls ||= [] }

  before { use_checks(fake_check("rubocop", :pass), fake_check("tests", :pass)) }

  describe "check mode" do
    it "checks the changed files and exits 0 when nothing failed" do
      touch(root, "app/models/post.rb", "class Post\nend\n")

      expect(run_cli).to eq(0)
      expect(stdout.string).to start_with("agent-check: PASS (rubocop, tests) - 1 file checked in")
      expect(calls).to eq([["rubocop", %w[app/models/post.rb]], ["tests", %w[app/models/post.rb]]])
    end

    it "exits 1 when a check failed" do
      use_checks(fake_check("rubocop", :fail, details: ["bad"]), fake_check("tests", :pass))

      expect(run_cli).to eq(1)
      expect(stdout.string).to include("agent-check: FAIL (rubocop)", "[rubocop] FAIL 1 problem", "  bad")
    end

    it "runs only the checks named with --only" do
      expect(run_cli("--only", "tests")).to eq(0)
      expect(calls.map(&:first)).to eq(%w[tests])
    end

    it "rejects unknown checks in --only" do
      expect(run_cli("--only", "nope")).to eq(1)
      expect(stderr.string).to include("unknown check: nope")
    end

    it "checks the files given with --files" do
      touch(root, "lib/x.rb", "x\n")

      run_cli("--files", "lib/x.rb,#{root}/app/models/post.rb,missing.rb")

      expect(calls.first).to eq(["rubocop", %w[lib/x.rb app/models/post.rb]])
      expect(stderr.string).to include("skipping missing.rb: no such file")
    end

    it "works out added files against --base when --files is given" do
      git(root, "checkout", "-q", "-b", "develop")
      touch(root, "db/migrate/add_x.rb", "class AddX < ActiveRecord::Migration[8.1]\nend\n")
      git(root, "add", "-A")
      git(root, "commit", "-q", "-m", "on develop")
      git(root, "checkout", "-q", "-b", "feature")
      use_checks(RailsAgentHarness::Checks::Migrations)

      run_cli("--files", "db/migrate/add_x.rb", "--base", "develop")
      expect(stdout.string).to start_with("agent-check: PASS")

      run_cli("--files", "db/migrate/add_x.rb", "--base", "main")
      expect(stdout.string).to include("db/migrate/add_x.rb: does not look generated")
    end

    it "falls back gracefully when --base doesn't resolve with --files" do
      use_checks(RailsAgentHarness::Checks::Migrations)
      touch(root, "db/migrate/20261030120000_add_x.rb", "class AddX < ActiveRecord::Migration[8.1]\nend\n")
      allow(RailsAgentHarness::ChangedFiles).to receive(:new).and_raise(RailsAgentHarness::Error, "not a git repository")

      expect(run_cli("--files", "db/migrate/20261030120000_add_x.rb", "--base", "nope")).to eq(1)
      expect(stdout.string).to include("migration added but db/schema.rb not updated")
      expect(stderr.string).to eq("agent-check: warning: --base nope: not a git repository; working out added files without it\n")
    end

    it "diffs against --base" do
      git(root, "checkout", "-q", "-b", "feature")
      touch(root, "app/models/comment.rb", "x\n")
      git(root, "add", "-A")
      git(root, "commit", "-q", "-m", "comment")

      run_cli("--base", "feature")
      expect(calls.first).to eq(["rubocop", []])

      run_cli("--base", "main")
      expect(calls.last).to eq(["tests", %w[app/models/comment.rb]])
    end

    it "truncates output to max_output_lines unless --verbose" do
      use_checks(fake_check("rubocop", :fail, details: %w[l1 l2 l3]))
      load_config(root, "max_output_lines: 1\n")

      run_cli
      expect(stdout.string).to include("... 2 more lines (run bin/agent-check --verbose)")

      run_cli("--verbose")
      expect(stdout.string).to include("l3")
    end

    it "prints help and the version" do
      expect(run_cli("--help")).to eq(0)
      expect(stdout.string).to include("Usage: bin/agent-check [options]", "--only CHECKS", "hook pre-tool-use|post-tool-use|stop")

      expect(run_cli("--version")).to eq(0)
      expect(stdout.string).to eq("agent-check #{RailsAgentHarness::VERSION}\n")
    end

    it "exits 1 on bad options" do
      expect(run_cli("--nope")).to eq(1)
      expect(stderr.string).to include("invalid option: --nope")
    end

    it "exits 1 with a one-line message on unexpected errors" do
      allow(RailsAgentHarness::Configuration).to receive(:load).and_raise(RuntimeError, "boom")

      expect(run_cli).to eq(1)
      expect(stderr.string).to eq("agent-check: RuntimeError: boom\n")
    end

    it "prefers an explicit root over CLAUDE_PROJECT_DIR" do
      @stdout = StringIO.new
      @stderr = StringIO.new
      status = described_class.start([], stdin: StringIO.new, stdout: @stdout, stderr: @stderr,
        env: {"CLAUDE_PROJECT_DIR" => "/nonexistent"}, root: root)

      expect(status).to eq(0)
      expect(stdout.string).to include("agent-check: PASS")
    end

    it "uses the git top level when CLAUDE_PROJECT_DIR is not set" do
      subdir = File.join(root, "app/models")
      Dir.chdir(subdir) { run_cli(env: {}) }

      expect(stdout.string).to include("agent-check: PASS")
    end
  end

  describe "hook post-tool-use" do
    def payload(file_path)
      JSON.generate("tool_name" => "Write", "tool_input" => {"file_path" => file_path})
    end

    it "runs only rubocop on the edited file and prints nothing on success" do
      expect(run_cli("hook", "post-tool-use", stdin: payload(File.join(root, "app/models/post.rb")))).to eq(0)

      expect(calls).to eq([["rubocop", %w[app/models/post.rb]]])
      expect(stdout.string + stderr.string).to be_empty
    end

    it "exits 2 with the report on stderr when rubocop fails" do
      use_checks(fake_check("rubocop", :fail, details: ["app/models/post.rb:1:1: C: Bad"]))

      expect(run_cli("hook", "post-tool-use", stdin: payload(File.join(root, "app/models/post.rb")))).to eq(2)
      expect(stderr.string).to include("[rubocop] FAIL", "app/models/post.rb:1:1: C: Bad")
      expect(stdout.string).to be_empty
    end

    it "accepts a root-relative file_path" do
      expect(run_cli("hook", "post-tool-use", stdin: payload("app/models/post.rb"))).to eq(0)
      expect(calls).to eq([["rubocop", %w[app/models/post.rb]]])
    end

    it "ignores files outside the project, missing files and bad input with exit 0" do
      expect(run_cli("hook", "post-tool-use", stdin: payload("/etc/hosts"))).to eq(0)
      expect(stderr.string).to include("/etc/hosts is outside the project; skipping")

      expect(run_cli("hook", "post-tool-use", stdin: payload(File.join(root, "gone.rb")))).to eq(0)

      expect(run_cli("hook", "post-tool-use", stdin: "not json")).to eq(0)
      expect(stderr.string).to include("invalid hook input JSON")

      expect(run_cli("hook", "post-tool-use", stdin: "")).to eq(0)
      expect(run_cli("hook", "post-tool-use", stdin: "[]")).to eq(0)
      expect(run_cli("hook", "post-tool-use", stdin: JSON.generate("tool_input" => {}))).to eq(0)
      expect(stderr.string).to include("no tool_input.file_path")
      expect(run_cli("hook", "post-tool-use", stdin: JSON.generate("tool_input" => "bad"))).to eq(0)
      expect(stderr.string).to include("no tool_input.file_path")
      expect(calls).to be_empty
    end

    it "exits 1 (never 2) on unexpected errors" do
      allow(RailsAgentHarness::Configuration).to receive(:load).and_raise(RailsAgentHarness::ConfigurationError, "bad config")

      expect(run_cli("hook", "post-tool-use", stdin: payload(File.join(root, "app/models/post.rb")))).to eq(1)
      expect(stderr.string).to include("bad config")
    end
  end

  describe "hook stop" do
    before { touch(root, "app/models/post.rb", "class Post\nend\n") }

    it "runs the full check and exits 0 when it passes" do
      expect(run_cli("hook", "stop", stdin: JSON.generate("stop_hook_active" => false))).to eq(0)
      expect(calls.map(&:first)).to eq(%w[rubocop tests])
      expect(stdout.string + stderr.string).to be_empty
    end

    it "exits 2 with the report on stderr when a check fails" do
      use_checks(fake_check("tests", :fail, details: ["rspec ./spec/x_spec.rb:1 # x"]))

      expect(run_cli("hook", "stop", stdin: "{}")).to eq(2)
      expect(stderr.string).to include("agent-check: FAIL (tests)", "rspec ./spec/x_spec.rb:1 # x")
    end

    it "exits 0 immediately when stop_hook_active is true" do
      use_checks(fake_check("tests", :fail))

      expect(run_cli("hook", "stop", stdin: JSON.generate("stop_hook_active" => true))).to eq(0)
      expect(calls).to be_empty
    end

    it "exits 0 on invalid input" do
      expect(run_cli("hook", "stop", stdin: "{")).to eq(0)
      expect(calls).to be_empty
    end
  end

  describe "hook pre-tool-use" do
    def payload(tool, file_path)
      JSON.generate("tool_name" => tool, "tool_input" => {"file_path" => file_path})
    end

    it "exits 2 with the reason on stderr when the guard blocks" do
      expect(run_cli("hook", "pre-tool-use", stdin: payload("Edit", File.join(root, "db/schema.rb")))).to eq(2)
      expect(stderr.string).to eq("db/schema.rb is generated by Rails. Do not edit it by hand: change the schema " \
        "with a migration (bin/rails g migration ...) and run bin/rails db:migrate.\n")

      expect(run_cli("hook", "pre-tool-use", stdin: payload("Write", File.join(root, "db/migrate/20990101000000_x.rb")))).to eq(2)
      expect(stderr.string).to start_with("Do not hand-write migration files.")
    end

    it "exits 0 silently when allowed" do
      expect(run_cli("hook", "pre-tool-use", stdin: payload("Write", File.join(root, "app/models/post.rb")))).to eq(0)
      expect(stdout.string + stderr.string).to be_empty
      expect(run_cli("hook", "pre-tool-use", stdin: JSON.generate("tool_name" => "Bash", "tool_input" => {"command" => "bin/rails g migration X"}))).to eq(0)
    end

    it "exits 0 with a warning on bad input, and 1 on internal errors" do
      expect(run_cli("hook", "pre-tool-use", stdin: "nope")).to eq(0)
      expect(stderr.string).to include("invalid hook input JSON")

      allow(RailsAgentHarness::Configuration).to receive(:load).and_raise(RailsAgentHarness::ConfigurationError, "bad config")
      expect(run_cli("hook", "pre-tool-use", stdin: payload("Edit", "db/schema.rb"))).to eq(1)
    end

    it "honors guards disabled in config" do
      load_config(root, "guards:\n  schema:\n    enabled: false\n")

      expect(run_cli("hook", "pre-tool-use", stdin: payload("Edit", File.join(root, "db/schema.rb")))).to eq(0)
    end
  end

  it "exits 1 for an unknown hook event" do
    expect(run_cli("hook", "nope", stdin: "{}")).to eq(1)
    expect(stderr.string).to include("unknown hook \"nope\"")
  end

  it "doesn't load Rails" do
    lib = File.expand_path("../../lib", __dir__)
    output, status = Open3.capture2e("ruby", "-I", lib, "-e", 'require "rails_agent_harness/cli"; print defined?(Rails) ? "rails" : "no rails"')

    expect(status).to be_success, output
    expect(output).to eq("no rails")
  end
end
