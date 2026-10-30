# frozen_string_literal: true

require "rails_agent_harness/app_detector"
require "rails_agent_harness/command_runner"

# Builders for check, runner and CLI specs.
module AgentCheckHelper
  # Records every command (and its options) and returns a canned CommandRunner::Result.
  # `stderr` is only kept apart from stdout when the command asks for `separate_stderr`.
  class FakeRunner
    attr_reader :calls, :options

    def initialize(output: "", exit_status: 0, stderr: "")
      @output = output
      @stderr = stderr
      @exit_status = exit_status
      @calls = []
      @options = []
    end

    def call(*argv, **options)
      @calls << argv
      @options << options
      stdout = options[:separate_stderr] ? @output : @output + @stderr
      RailsAgentHarness::CommandRunner::Result.new(output: @output + @stderr, exit_status: @exit_status, duration: 0.01, stdout: stdout)
    end
  end

  def build_profile(**overrides)
    RailsAgentHarness::AppProfile.new(
      rails_version: "8.1.4", test_framework: :rspec, database: :sqlite,
      rubocop: true, standard: false, brakeman: true, schema_format: :ruby, **overrides
    )
  end

  def load_config(root, yaml = nil)
    if yaml
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config/agent_harness.yml"), yaml)
    end
    RailsAgentHarness::Configuration.load(root)
  end

  def touch(root, relative, contents = "", executable: false)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    FileUtils.chmod(0o755, path) if executable
    path
  end

  # Runs git in `dir`, raising on failure.
  def git(dir, *args)
    output, status = Open3.capture2e("git", "-c", "user.email=test@example.com", "-c", "user.name=Test", *args, chdir: dir)
    raise "git #{args.join(" ")} failed: #{output}" unless status.success?

    output
  end

  # A tmp git repo on `main` with one commit containing `files` (path => contents).
  def with_git_repo(files = {"README.md" => "readme\n"})
    Dir.mktmpdir("agent_harness_git") do |dir|
      git(dir, "init", "-q", "-b", "main")
      files.each { |path, contents| touch(dir, path, contents) }
      git(dir, "add", "-A")
      git(dir, "commit", "-q", "-m", "init")
      yield dir
    end
  end
end

RSpec.configure { |config| config.include AgentCheckHelper }
