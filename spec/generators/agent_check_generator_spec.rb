# frozen_string_literal: true

require "json"
require "generators/agent_harness/install/install_generator"

RSpec.describe AgentHarness::Generators::InstallGenerator, "bin/agent-check and Claude Code hooks" do
  around do |example|
    Dir.mktmpdir("agent_harness_install") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root, :exit_status

  def run_generator(args = [])
    output = StringIO.new
    original = [$stdout, $stderr]
    $stdout = output
    $stderr = StringIO.new
    @exit_status = 0
    begin
      described_class.start(args, destination_root: root)
    rescue SystemExit => e
      @exit_status = e.status
    end
    output.string
  ensure
    $stdout, $stderr = original
  end

  def settings_path = File.join(root, ".claude/settings.json")

  def settings = JSON.parse(File.read(settings_path))

  def hook_commands(event)
    settings.dig("hooks", event).flat_map { |group| group["hooks"].map { |hook| hook["command"] } }
  end

  describe "bin/agent-check" do
    it "is created executable and loads the CLI without Rails" do
      run_generator
      binstub = File.join(root, "bin/agent-check")

      expect(File.executable?(binstub)).to be(true)
      expect(File.read(binstub)).to start_with("#!/usr/bin/env ruby\n# frozen_string_literal: true\n")
      expect(File.read(binstub)).to include('require "bundler/setup"', 'require "rails_agent_harness/cli"', "exit RailsAgentHarness::CLI.start(ARGV)")
    end
  end

  describe ".claude/settings.json" do
    it "is created with the PostToolUse and Stop hooks" do
      run_generator

      expect(settings).to eq(
        "$schema" => "https://json.schemastore.org/claude-code-settings.json",
        "hooks" => {
          "PostToolUse" => [{
            "matcher" => "Edit|Write",
            "hooks" => [{"type" => "command", "command" => "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook post-tool-use", "timeout" => 60}]
          }],
          "Stop" => [{
            "hooks" => [{"type" => "command", "command" => "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook stop", "timeout" => 300}]
          }]
        }
      )
      expect(File.read(settings_path)).to end_with("}\n")
    end

    it "merges into existing settings, keeping unrelated keys and hooks" do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.generate(
        "permissions" => {"allow" => ["Bash(bin/rails test:*)"]},
        "hooks" => {"PostToolUse" => [{"matcher" => "Bash", "hooks" => [{"type" => "command", "command" => "audit.sh"}]}]}
      ))

      run_generator

      expect(settings["permissions"]).to eq("allow" => ["Bash(bin/rails test:*)"])
      expect(settings).not_to have_key("$schema")
      expect(hook_commands("PostToolUse")).to eq(["audit.sh", "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook post-tool-use"])
      expect(hook_commands("Stop")).to eq(["\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook stop"])
    end

    it "is idempotent" do
      run_generator
      first = File.read(settings_path)

      output = run_generator

      expect(File.read(settings_path)).to eq(first)
      expect(output).to include("identical  .claude/settings.json")
    end

    it "doesn't add an entry when an existing hook already runs the same bin/agent-check hook" do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.generate(
        "hooks" => {"Stop" => [{"hooks" => [{"type" => "command", "command" => "bin/agent-check hook stop --verbose"}]}]}
      ))

      run_generator

      expect(hook_commands("Stop")).to eq(["bin/agent-check hook stop --verbose"])
      expect(hook_commands("PostToolUse")).to eq(["\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook post-tool-use"])
    end

    it "leaves invalid JSON untouched and exits non-zero" do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, "{ not json")

      output = run_generator

      expect(File.read(settings_path)).to eq("{ not json")
      expect(output).to include("error  .claude/settings.json is not valid JSON")
      expect(exit_status).to eq(1)
    end

    it "leaves an unexpected structure untouched" do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.generate("hooks" => {"Stop" => {"not" => "an array"}}))

      run_generator

      expect(settings["hooks"]["Stop"]).to eq("not" => "an array")
      expect(exit_status).to eq(1)
    end

    it "is skipped with --skip-claude-hooks" do
      run_generator(["--skip-claude-hooks"])

      expect(File).not_to exist(settings_path)
      expect(File).to exist(File.join(root, "bin/agent-check"))
    end
  end

  describe "AGENTS.md" do
    it "adds the Verify your work section after the conventions" do
      run_generator
      agents = File.read(File.join(root, "AGENTS.md"))

      expect(agents.index("## Rails conventions")).to be < agents.index("## Verify your work")
      expect(agents).to include(
        "Run `bin/agent-check` before you say a task is done",
        "merge base with `main`",
        "`bin/agent-check --only rubocop,tests`", "`--files app/models/post.rb`", "`--verbose`",
        "| `app/views/<resource>/**` | `spec/requests/<resource>_spec.rb` | `test/controllers/<resource>_controller_test.rb` |",
        "`config/agent_harness.yml`"
      )
    end

    it "uses the configured base branch" do
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config/agent_harness.yml"), "base_branch: develop\n")

      run_generator

      expect(File.read(File.join(root, "AGENTS.md"))).to include("merge base with `develop`")
    end

    it "documents the same test mapping as the Tests check" do
      run_generator
      agents = File.read(File.join(root, "AGENTS.md"))
      source = File.read(File.expand_path("../../lib/rails_agent_harness/checks/tests.rb", __dir__))

      %w[spec/requests/<path>_spec.rb test/integration/<path>_test.rb spec/lib/<path>_spec.rb test/lib/<path>_test.rb].each do |target|
        expect(agents).to include(target)
        expect(source).to include(target)
      end
    end
  end
end
