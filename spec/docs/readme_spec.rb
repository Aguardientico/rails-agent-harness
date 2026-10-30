# frozen_string_literal: true

require "generators/agent_harness/install/install_generator"
require "rails_agent_harness/cli"

RSpec.describe "README.md" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:readme) { File.read(File.join(root, "README.md")) }

  def section(title)
    readme[/^## #{Regexp.escape(title)}\n(.*?)(?=^## |\z)/m, 1] or raise "no ## #{title} section"
  end

  def flatten(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flatten(value, path) : [path]
    end
  end

  it "has the sections in order" do
    titles = readme.scan(/^## (.+)$/).flatten

    expect(titles).to eq(["Why", "Before / after", "Install", "How it works with each agent", "`bin/agent-check`",
      "Configuration", "Migration guard", "Compatibility", "Development", "Open core", "License"])
  end

  it "documents every configuration key with its default" do
    configuration = section("Configuration")

    flatten(RailsAgentHarness::Configuration::DEFAULTS).each do |key|
      expect(configuration).to include("`#{key}`"), "missing #{key}"
    end
    RailsAgentHarness::Configuration::DEFAULTS.each do |key, value|
      expect(configuration).to include("#{key}: #{value}") unless value.is_a?(Hash)
    end
  end

  it "documents every bin/agent-check flag and hook" do
    help = StringIO.new
    RailsAgentHarness::CLI.start(["--help"], stdout: help, stderr: StringIO.new)
    flags = help.string.scan(/(?<=\s)--?[a-z][a-z-]*/).uniq

    expect(flags).to include("--only", "--files", "--base", "--verbose", "--version", "-h", "--help")
    flags.each { |flag| expect(section("`bin/agent-check`")).to include(flag) }
    RailsAgentHarness::CLI::HOOKS.each_key { |event| expect(readme).to include("bin/agent-check hook #{event}") }
    RailsAgentHarness::Checks.registry.each { |check| expect(section("`bin/agent-check`")).to include("`#{check.check_name}`") }
  end

  it "documents the generator's options and files" do
    options = AgentHarness::Generators::InstallGenerator.class_options.keys.map { |name| "--#{name.to_s.tr("_", "-")}" }

    %w[--force --skip-claude-hooks --skip-skills].each do |option|
      expect(options).to include(option)
      expect(section("Install")).to include("`#{option}`")
    end
    %w[AGENTS.md CLAUDE.md config/agent_harness.yml bin/agent-check .claude/settings.json .claude/skills/rails-review/SKILL.md].each do |file|
      expect(section("Install")).to include(file)
    end
  end

  it "quotes the demo transcript verbatim" do
    output = File.read(File.join(root, "demo/OUTPUT.md"))
    blocks = section("Before / after").scan(/```console\n(.*?)```/m).flatten

    expect(blocks.size).to eq(3)
    blocks.each { |block| expect(output).to include(block) }
  end

  it "has the same test mapping table as AGENTS.md" do
    partial = File.read(File.join(root, "lib/generators/agent_harness/install/templates/agents_md/30_agent_check.md.tt"))
    table = partial[/^\| Changed file .*?(?=\n\n)/m]

    expect(section("`bin/agent-check`")).to include(table)
  end

  it "links files that exist" do
    readme.scan(/\]\(((?!https?:|#)[^)]+)\)/).flatten.each do |link|
      expect(File).to exist(File.join(root, link)), "broken link #{link}"
    end
  end
end

RSpec.describe "CHANGELOG.md and RELEASING.md" do
  let(:root) { File.expand_path("../..", __dir__) }

  it "has an Unreleased header above the 0.1.0 entry" do
    changelog = File.read(File.join(root, "CHANGELOG.md"))

    expect(changelog).to include("keepachangelog.com/en/1.1.0", "Semantic Versioning")
    expect(changelog.index("## [Unreleased]")).to be < changelog.index("## [#{RailsAgentHarness::VERSION}] - Unreleased")
  end

  it "describes the manual release without automating it" do
    releasing = File.read(File.join(root, "RELEASING.md"))

    expect(releasing).to include("gem build rails_agent_harness.gemspec", "gem push", "git tag", "MFA")
  end
end
