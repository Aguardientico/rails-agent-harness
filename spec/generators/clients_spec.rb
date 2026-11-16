# frozen_string_literal: true

require "generators/agent_harness/install/install_generator"
require "rails_agent_harness/installation"
require "open3"

RSpec.describe AgentHarness::Generators::InstallGenerator, "client installation" do
  around do |example|
    Dir.mktmpdir("clients") do |root|
      @root = root
      example.run
    end
  end

  def install(args = [])
    described_class.start(args, destination_root: @root, shell: Thor::Shell::Basic.new)
  end

  def manifest
    JSON.parse(File.read(File.join(described_class.source_root, "clients.json")))
  end

  it "installs identical skills, client-specific hooks and instructions, idempotently" do
    install
    skills = manifest.fetch("skills").map { |path| File.read(File.join(@root, path)) }
    expect(skills.uniq.size).to eq(1)
    before = Dir.glob(File.join(@root, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
    install
    expect(before.keys.to_h { |path| [path, File.binread(path)] }).to eq(before)
    expect(RailsAgentHarness::Installation.verify(@root)).to be_empty
    manifest.fetch("clients").each_value do |client|
      expect(JSON.parse(File.read(File.join(@root, client.fetch("path"))))).to eq(client.fetch("config"))
    end
  end

  it "resolves Codex and Gemini hook commands from a session subdirectory with spaces" do
    install
    expect(system("git", "init", "-q", @root)).to be(true)
    subdir = File.join(@root, "app/models with spaces")
    FileUtils.mkdir_p(subdir)
    File.write(File.join(@root, "bin/agent-check"), "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
    %w[codex gemini].each do |client|
      manifest.fetch("clients").fetch(client).fetch("config").fetch("hooks").each_value do |groups|
        command = groups.first.fetch("hooks").first.fetch("command")
        output, status = Open3.capture2e({"GEMINI_PROJECT_DIR" => @root}, "sh", "-c", command, chdir: subdir)
        expect(status).to be_success
        expect(output.lines.map(&:chomp)).to eq(["client-hook", client, command.split.last])
      end
    end
  end

  it "limits tool hooks to supported file mutations" do
    clients = manifest.fetch("clients")
    {"codex" => [%w[PreToolUse PostToolUse], %w[apply_patch Edit Write]],
     "gemini" => [%w[BeforeTool AfterTool], %w[write_file replace]],
     "cursor" => [["preToolUse"], %w[Write Delete]]}.each do |client, (events, tools)|
      events.each do |event|
        matcher = Regexp.new(clients.fetch(client).fetch("config").fetch("hooks").fetch(event).first.fetch("matcher"))
        tools.each { |tool| expect(matcher).to match(tool) }
        %w[Read Grep Shell Bash exec_command run_shell_command read_file].each { |tool| expect(matcher).not_to match(tool) }
      end
    end
  end

  it "preserves formatting and timestamps of already merged client settings" do
    install
    paths = manifest.fetch("clients").values.map { |client| File.join(@root, client.fetch("path")) }
    originals = paths.to_h do |path|
      contents = JSON.generate(JSON.parse(File.read(path)))
      File.write(path, contents)
      File.utime(Time.at(1), Time.at(1), path)
      [path, contents]
    end
    install
    originals.each do |path, contents|
      expect(File.read(path)).to eq(contents)
      expect(File.mtime(path)).to eq(Time.at(1))
    end
  end

  it "keeps Claude hooks inert when another client imports its settings, and upgrades old commands" do
    legacy = '"${CLAUDE_PROJECT_DIR}"/bin/agent-check hook pre-tool-use'
    path = File.join(@root, ".claude/settings.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate("hooks" => {"PreToolUse" => [{"matcher" => "Edit|Write", "hooks" => [{"type" => "command", "command" => legacy}]}]}))
    install
    hooks = JSON.parse(File.read(path)).dig("hooks", "PreToolUse")
    expect(hooks.size).to eq(1)
    command = hooks.first.fetch("hooks").first.fetch("command")
    File.write(File.join(@root, "bin/agent-check"), "#!/bin/sh\nexit 2\n")
    output, status = Open3.capture2e({"CLAUDE_PROJECT_DIR" => nil}, "sh", "-c", command, chdir: @root)
    expect(status.exitstatus).to eq(0)
    expect(output).to eq("")
    _, status = Open3.capture2e({"CLAUDE_PROJECT_DIR" => @root}, "sh", "-c", command, chdir: @root)
    expect(status.exitstatus).to eq(2)
  end

  it "does not mask root user instructions in Junie" do
    File.write(File.join(@root, "AGENTS.md"), "User instructions\n")
    install
    expect(File).not_to exist(File.join(@root, ".junie/AGENTS.md"))
    expect(File.read(File.join(@root, "AGENTS.md"))).to include("User instructions")
  end

  it "updates existing Junie instructions without replacing their content" do
    path = File.join(@root, ".junie/AGENTS.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "Existing Junie instructions\n")
    install
    expect(File.read(path)).to include("Existing Junie instructions", "## Verify your work")
  end

  it "preserves hook timeout changes without duplicating a command" do
    install
    path = File.join(@root, ".codex/hooks.json")
    config = JSON.parse(File.read(path))
    config["hooks"]["Stop"].first["hooks"].first["timeout"] = 123
    File.write(path, JSON.generate(config))
    install
    expect(JSON.parse(File.read(path)).dig("hooks", "Stop").size).to eq(1)
    expect(JSON.parse(File.read(path)).dig("hooks", "Stop", 0, "hooks", 0, "timeout")).to eq(123)
  end

  it "refuses a different Aider config and can replace client artifacts without resetting checks" do
    File.write(File.join(@root, ".aider.agent-harness.yml"), "auto-test: false\n")
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "config/agent_harness.yml"), "base_branch: develop\n")
    expect { install }.to raise_error(SystemExit)
    install(%w[--force-client-files])
    expect(File.read(File.join(@root, "config/agent_harness.yml"))).to eq("base_branch: develop\n")
    expect(RailsAgentHarness::Installation.verify(@root)).to be_empty
  end

  it "reads non-ASCII existing settings under a non-UTF-8 default encoding" do
    path = File.join(@root, ".gemini/settings.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate("theme" => "revisión"))
    original = Encoding.default_external
    Encoding.default_external = Encoding::US_ASCII
    install
    expect(JSON.parse(File.read(path, encoding: "UTF-8"))["theme"]).to eq("revisión")
  ensure
    Encoding.default_external = original
  end

  it "supports dry runs without requiring installed files" do
    install(%w[--pretend])
    expect(Dir.children(@root)).to be_empty
  end

  it "preserves user settings and hooks" do
    path = File.join(@root, ".gemini/settings.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate("theme" => "custom", "hooks" => {"BeforeTool" => [{"hooks" => [{"type" => "command", "command" => "my-hook"}]}]}))
    install
    settings = JSON.parse(File.read(path))
    expect(settings["theme"]).to eq("custom")
    expect(settings["hooks"]["BeforeTool"].size).to eq(2)
  end

  it "fails without touching invalid configurations" do
    path = File.join(@root, ".cursor/hooks.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "invalid")
    expect { install }.to raise_error(SystemExit)
    expect(File.read(path)).to eq("invalid")
  end

  it "detects missing hooks and skill drift after installation" do
    install
    File.delete(File.join(@root, ".codex/hooks.json"))
    File.write(File.join(@root, ".agents/skills/rails-review/SKILL.md"), "changed")
    expect(RailsAgentHarness::Installation.verify(@root).join).to include("missing installed file", "differs from installation")
  end

  it "ignores user configuration changes while checking managed blocks and hooks" do
    install
    File.open(File.join(@root, "AGENTS.md"), "a") { |file| file.puts "\nUser guidance\n" }
    File.write(File.join(@root, "config/agent_harness.yml"), "base_branch: develop\n")
    path = File.join(@root, ".gemini/settings.json")
    settings = JSON.parse(File.read(path)).merge("theme" => "custom")
    File.write(path, JSON.generate(settings))
    expect(RailsAgentHarness::Installation.verify(@root)).to be_empty
    settings["hooks"].delete("BeforeTool")
    File.write(path, JSON.generate(settings))
    expect(RailsAgentHarness::Installation.verify(@root).join).to include("missing managed BeforeTool hook")
    agents = File.join(@root, "AGENTS.md")
    File.write(agents, File.read(agents).sub("## Verify your work", "## Changed managed block"))
    expect(RailsAgentHarness::Installation.verify(@root).join).to include("managed content differs")
  end

  it "supports opt-outs without reporting missing optional artifacts" do
    install(%w[--skip-skills --skip-client-hooks --skip-claude-hooks])
    expect(RailsAgentHarness::Installation.verify(@root)).to be_empty
    expect(File).not_to exist(File.join(@root, ".codex/hooks.json"))
    expect(File).not_to exist(File.join(@root, ".agents/skills/rails-review/SKILL.md"))
  end
end
