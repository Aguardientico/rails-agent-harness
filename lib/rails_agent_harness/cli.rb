# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "rails_agent_harness"
require "rails_agent_harness/app_detector"
require "rails_agent_harness/changed_files"
require "rails_agent_harness/guards/migration_guard"
require "rails_agent_harness/paths"
require "rails_agent_harness/runner"

module RailsAgentHarness
  # `bin/agent-check`. Never loads Rails or the host app.
  #
  #   bin/agent-check [options]      check the change set; exit 0 (pass) or 1 (failure)
  #   bin/agent-check hook EVENT     Claude Code hook: exit 0 (pass, skip or bad input),
  #                                  2 (check failure, report on stderr) or 1 (harness error)
  class CLI
    # Hook event (as passed on the command line) => method handling it.
    HOOKS = {"pre-tool-use" => :pre_tool_use_hook, "post-tool-use" => :post_tool_use_hook, "stop" => :stop_hook}

    # `root` is the app directory; the generated binstub passes its own app so the right app is
    # checked even when it lives in a subdirectory of a larger repository.
    def self.start(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV, root: nil)
      new(stdin: stdin, stdout: stdout, stderr: stderr, env: env, root: root).run(argv.dup)
    end

    def initialize(stdin:, stdout:, stderr:, env:, root: nil)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @env = env
      @root = File.expand_path(root) if root
    end

    def run(argv)
      return hook(argv[1]) if argv.first == "hook"

      check(argv)
    rescue => e
      @stderr.puts "agent-check: #{e.class}: #{e.message}"
      1
    end

    private

    def check(argv)
      options = parse_options(argv)
      return options if options.is_a?(Integer)

      config = Configuration.load(root)
      if options[:files]
        files = options[:files]
        # With --base, "added" (for the migrations check) is worked out against that branch;
        # outside a git repository the check falls back on its own.
        if options[:base]
          added = begin
            ChangedFiles.new(root, base_branch: options[:base]).added
          rescue Error => e
            @stderr.puts "agent-check: warning: --base #{options[:base]}: #{e.message}; working out added files without it"
            nil
          end
        end
      else
        changes = ChangedFiles.new(root, base_branch: options[:base] || config.base_branch)
        files = changes.list
        added = changes.added
      end
      report = runner(config, files, options[:only], added: added).call
      @stdout.puts report.to_s(max_lines: config.max_output_lines, verbose: options[:verbose])
      report.failed? ? 1 : 0
    end

    def parse_options(argv)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/agent-check [options]\n       bin/agent-check hook #{HOOKS.keys.join("|")}"
        opts.separator ""
        opts.separator "Runs fast checks (#{Checks.registry.map(&:check_name).join(", ")}) on the files changed since the merge base."
        opts.separator "Exit status: 0 when nothing failed, 1 otherwise."
        opts.separator ""
        opts.on("--only CHECKS", Array, "Run only these checks (comma-separated)") { |names| options[:only] = names }
        opts.on("--files FILES", Array, "Check these files instead of the changed files") { |files| options[:files] = files }
        opts.on("--base BRANCH", "Branch to diff against (default: base_branch in config)") { |base| options[:base] = base }
        opts.on("--verbose", "Don't truncate check output") { options[:verbose] = true }
        opts.on("--version", "Print the version") do
          @stdout.puts "agent-check #{VERSION}"
          return 0
        end
        opts.on("-h", "--help", "Print this help") do
          @stdout.puts opts
          return 0
        end
      end
      parser.parse!(argv)
      unknown = Array(options[:only]) - Checks.registry.map(&:check_name)
      return usage_error("unknown check: #{unknown.join(", ")}") if unknown.any?
      return usage_error("unexpected argument: #{argv.join(" ")}") if argv.any?

      options[:files] &&= normalize_files(options[:files])
      options
    rescue OptionParser::ParseError => e
      usage_error(e.message)
    end

    def usage_error(message)
      @stderr.puts "agent-check: #{message} (see bin/agent-check --help)"
      1
    end

    def normalize_files(files)
      files.map { |file| relative_path(file) || file }.select do |file|
        File.file?(File.join(root, file)).tap { |exists| @stderr.puts "agent-check: skipping #{file}: no such file" unless exists }
      end
    end

    def hook(event)
      handler = HOOKS[event]
      unless handler
        @stderr.puts "agent-check: unknown hook #{event.inspect} (expected #{HOOKS.keys.join(", ")})"
        return 1
      end

      payload = read_hook_payload or return 0
      send(handler, payload)
    end

    # Before Write/Edit: the migration/schema guard. Blocked calls exit 2 with the reason on
    # stderr (Claude Code blocks the tool call and shows it to the model). No git, no
    # subprocesses.
    def pre_tool_use_hook(payload)
      decision = Guards::MigrationGuard.new(root: root, config: Configuration.load(root)).pre_tool_use(payload)
      return 0 if decision.allowed?

      @stderr.puts decision.message
      2
    end

    # After Write/Edit: RuboCop on the edited file only, to stay fast.
    def post_tool_use_hook(payload)
      tool_input = payload["tool_input"]
      file_path = tool_input["file_path"] if tool_input.is_a?(Hash)
      return ignore_hook("no tool_input.file_path in hook input") unless file_path.is_a?(String) && !file_path.empty?

      file = relative_path(file_path)
      return ignore_hook("#{file_path} is outside the project") unless file
      return 0 unless File.file?(File.join(root, file))

      config = Configuration.load(root)
      report_hook(runner(config, [file], ["rubocop"]).call, config)
    end

    # When Claude is about to finish: the full check. `stop_hook_active` means Claude is
    # already continuing because of a Stop hook, so let it stop rather than loop.
    def stop_hook(payload)
      return 0 if payload["stop_hook_active"] == true

      config = Configuration.load(root)
      changes = ChangedFiles.new(root, base_branch: config.base_branch)
      report_hook(runner(config, changes.list, nil, added: changes.added).call, config)
    end

    # Exit 2 with the report on stderr (Claude Code feeds it back to the model) on failure.
    def report_hook(report, config)
      return 0 unless report.failed?

      @stderr.puts report.to_s(max_lines: config.max_output_lines)
      2
    end

    def read_hook_payload
      payload = JSON.parse(@stdin.read.to_s)
      return payload if payload.is_a?(Hash)

      ignore_hook("hook input is not a JSON object")
      nil
    rescue JSON::ParserError => e
      ignore_hook("invalid hook input JSON (#{e.message.lines.first.strip})")
      nil
    end

    def ignore_hook(reason)
      @stderr.puts "agent-check: #{reason}; skipping"
      0
    end

    def runner(config, files, only, added: nil)
      checks = only ? only.map { |name| Checks.find(name) } : Checks.registry
      Runner.new(root: root, config: config, profile: AppDetector.new(root).detect, files: files, added: added, checks: checks)
    end

    # The project root: the one passed to .start, else $CLAUDE_PROJECT_DIR, else the git top
    # level, else the current directory.
    def root
      @root ||= begin
        dir = @env["CLAUDE_PROJECT_DIR"].to_s
        if dir.empty?
          output, status = Open3.capture2e("git", "rev-parse", "--show-toplevel")
          dir = status.success? ? output.strip : Dir.pwd
        end
        File.expand_path(dir)
      end
    end

    # `path` relative to the project root, or nil when it is outside it.
    def relative_path(path)
      Paths.relative(path, root)
    end
  end
end
