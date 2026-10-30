# frozen_string_literal: true

require "erb"
require "json"
require "rails/generators"
require "rails_agent_harness"
require "rails_agent_harness/app_detector"

module AgentHarness
  module Generators
    class InstallGenerator < Rails::Generators::Base
      BEGIN_MARKER = "<!-- BEGIN rails_agent_harness -->"
      END_MARKER = "<!-- END rails_agent_harness -->"
      MARKED_BLOCK = /#{Regexp.escape(BEGIN_MARKER)}.*?#{Regexp.escape(END_MARKER)}\n?/m
      MARKER = /#{Regexp.escape(BEGIN_MARKER)}|#{Regexp.escape(END_MARKER)}/

      # Our Claude Code hook entries, by event. The command identifies an entry when merging.
      CLAUDE_HOOKS = {
        "PreToolUse" => {
          "matcher" => "Edit|Write",
          "hooks" => [{"type" => "command", "command" => "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook pre-tool-use", "timeout" => 10}]
        },
        "PostToolUse" => {
          "matcher" => "Edit|Write",
          "hooks" => [{"type" => "command", "command" => "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook post-tool-use", "timeout" => 60}]
        },
        "Stop" => {
          "hooks" => [{"type" => "command", "command" => "\"${CLAUDE_PROJECT_DIR}\"/bin/agent-check hook stop", "timeout" => 300}]
        }
      }.freeze
      CLAUDE_SETTINGS_SCHEMA = "https://json.schemastore.org/claude-code-settings.json"

      source_root File.expand_path("templates", __dir__)

      desc "Writes AGENTS.md, CLAUDE.md, config/agent_harness.yml and bin/agent-check tuned to this " \
        "app's stack, and wires bin/agent-check into Claude Code hooks."

      class_option :skip_claude_hooks, type: :boolean, default: false,
        desc: "Don't add bin/agent-check hooks to .claude/settings.json"
      class_option :skip_skills, type: :boolean, default: false,
        desc: "Don't write Claude Code skills (.claude/skills/)"

      # Exit non-zero when a step reports a problem (see #print_summary), like Rails' own
      # migration generator.
      def self.exit_on_failure? = true

      def create_config_file
        if File.exist?(File.join(destination_root, RailsAgentHarness::Configuration::PATH)) && !options[:force]
          say_status :exists, "#{RailsAgentHarness::Configuration::PATH} (skipped; use --force to overwrite)", :blue
        else
          template "agent_harness.yml.tt", RailsAgentHarness::Configuration::PATH
        end
      end

      def create_agents_md
        upsert_marked_block "AGENTS.md", agents_md
      end

      def create_claude_md
        if same_file?("CLAUDE.md", "AGENTS.md")
          return say_status(:skip, "CLAUDE.md (same file as AGENTS.md, which already has the instructions)", :yellow)
        end

        upsert_marked_block "CLAUDE.md", <<~MARKDOWN
          @AGENTS.md

          This project's agent instructions live in AGENTS.md (shared by Claude Code, Codex and Cursor). Read it before making changes.
        MARKDOWN
      end

      def create_agent_check_binstub
        template "bin/agent-check.tt", "bin/agent-check"
        chmod "bin/agent-check", 0o755
      end

      def configure_claude_hooks
        return if options[:skip_claude_hooks]

        merge_claude_hooks(CLAUDE_HOOKS)
      end

      # The skill is fully owned by the gem (no markers): an existing, different file is kept
      # unless --force, without Thor's interactive prompt (which overwrites on EOF, e.g. when an
      # agent runs the generator).
      def create_review_skill
        return if options[:skip_skills]

        path = ".claude/skills/rails-review/SKILL.md"
        full_path = File.join(destination_root, path)
        content = render_template("claude/skills/rails-review/SKILL.md.tt")
        if File.exist?(full_path) && File.read(full_path, encoding: "UTF-8") != content && !options[:force]
          return say_status(:exists, "#{path} (differs; kept, use --force to overwrite)", :blue)
        end

        create_file path, content, force: true
      end

      def print_summary
        say ""
        say "Detected stack:"
        say "  Rails version:  #{profile.rails_version || "unknown"}"
        say "  Test framework: #{profile.test_framework}"
        say "  Database:       #{profile.database}"
        say "  RuboCop:        #{profile.rubocop? ? "yes" : "no"}"
        say "  Standard:       #{profile.standard? ? "yes" : "no"}"
        say "  Brakeman:       #{profile.brakeman? ? "yes" : "no"}"
        say "  Schema format:  #{profile.schema_format}"
        say ""
        if problems.any?
          raise Thor::Error, "Some files were left unchanged and need fixing by hand:\n" +
            problems.map { |problem| "  - #{problem}" }.join("\n")
        end

        say "Next steps:"
        say "  1. Review AGENTS.md and config/agent_harness.yml."
        say "  2. Commit #{generated_files.join(", ")}."
      end

      private

      def profile
        @profile ||= RailsAgentHarness::AppDetector.new(destination_root).detect
      end

      # Every templates/agents_md/*.md.tt partial, sorted by filename and rendered with ERB in
      # this generator's binding. Later features add sections by adding partials (see README.md
      # in that directory).
      def agents_md
        Dir[File.join(self.class.source_root, "agents_md", "*.md.tt")].sort.map do |partial|
          render_template(partial).strip
        end.join("\n\n")
      end

      # The files this run manages, for the summary.
      def generated_files
        files = %w[AGENTS.md CLAUDE.md config/agent_harness.yml bin/agent-check]
        files << ".claude/settings.json" unless options[:skip_claude_hooks]
        files << ".claude/skills/rails-review/SKILL.md" unless options[:skip_skills]
        files
      end

      # Problems reported by steps; #print_summary turns them into a non-zero exit.
      def problems
        @problems ||= []
      end

      # Whether the markers in `text` are complete BEGIN/END pairs, in order.
      def markers_paired?(text)
        markers = text.scan(MARKER)
        markers.any? && markers.each_slice(2).all? { |pair| pair == [BEGIN_MARKER, END_MARKER] }
      end

      def same_file?(path, other)
        File.exist?(File.join(destination_root, path)) && File.exist?(File.join(destination_root, other)) &&
          File.identical?(File.join(destination_root, path), File.join(destination_root, other))
      end

      # Writes `content` between BEGIN/END markers in `path`: creates the file, appends the block
      # to a file without markers (keeping the user's content), or replaces the existing block
      # (extra blocks, if any, are removed). Unchanged content is left alone, so re-running is
      # idempotent. Unmatched BEGIN/END markers leave the file untouched and are reported as a
      # problem.
      def upsert_marked_block(path, content)
        block = "#{BEGIN_MARKER}\n#{content.strip}\n#{END_MARKER}\n"
        full_path = File.join(destination_root, path)
        return create_file(path, block) unless File.exist?(full_path)

        existing = File.read(full_path, encoding: "UTF-8")
        updated =
          if existing.include?(BEGIN_MARKER) || existing.include?(END_MARKER)
            unless markers_paired?(existing)
              problems << "#{path}: unmatched #{BEGIN_MARKER} / #{END_MARKER} markers"
              return say_status(:error, "#{path} has unmatched #{BEGIN_MARKER} / #{END_MARKER} markers; fix them and re-run", :red)
            end
            blocks = 0
            existing.gsub(MARKED_BLOCK) { ((blocks += 1) == 1) ? block : "" }
          elsif existing.strip.empty?
            block
          else
            "#{existing.rstrip}\n\n#{block}"
          end

        if updated == existing
          say_status :identical, path, :blue
        else
          create_file path, updated, force: !options[:skip]
        end
      end

      # Adds each event's entry (event => hook group) under `hooks` in .claude/settings.json,
      # creating the file if needed. Existing settings and hooks are kept, and an entry is
      # skipped when a hook command for that event already runs the same
      # `bin/agent-check hook ...`. Invalid JSON or an unexpected structure is reported and the
      # file is left untouched. Writes at most once.
      def merge_claude_hooks(entries)
        path = ".claude/settings.json"
        full_path = File.join(destination_root, path)
        settings = File.exist?(full_path) ? JSON.parse(File.read(full_path, encoding: "UTF-8")) : {"$schema" => CLAUDE_SETTINGS_SCHEMA}
        hooks = settings.is_a?(Hash) ? (settings["hooks"] ||= {}) : nil
        unless hooks.is_a?(Hash) && entries.keys.all? { |event| (hooks[event] ||= []).is_a?(Array) }
          problems << "#{path}: unexpected structure under \"hooks\"; add the bin/agent-check hooks by hand"
          return say_status(:error, "#{path}: unexpected structure under \"hooks\"; add the bin/agent-check hooks by hand", :red)
        end

        added = entries.reject { |event, entry| hook_command?(hooks[event], entry) }
        return say_status(:identical, path, :blue) if added.empty?

        added.each { |event, entry| hooks[event] << entry }
        create_file path, "#{JSON.pretty_generate(settings)}\n", force: true
      rescue JSON::ParserError => e
        problems << "#{path}: invalid JSON; add the bin/agent-check hooks by hand"
        say_status :error, "#{path} is not valid JSON (#{e.message.lines.first.strip}); add the bin/agent-check hooks by hand", :red
      end

      # Whether any hook in `groups` already runs the `bin/agent-check hook <event>` of `entry`.
      def hook_command?(groups, entry)
        signature = entry["hooks"].first["command"][%r{bin/agent-check hook \S+}]
        groups.any? do |group|
          group.is_a?(Hash) && Array(group["hooks"]).any? { |hook| hook.is_a?(Hash) && hook["command"].to_s.include?(signature) }
        end
      end

      # base_branch from config/agent_harness.yml (written by the first step), for templates.
      def base_branch
        RailsAgentHarness::Configuration.load(destination_root).base_branch
      rescue RailsAgentHarness::ConfigurationError
        RailsAgentHarness::Configuration::DEFAULTS["base_branch"]
      end

      # A rendered templates/shared/_rails_review_<name>.md.tt partial, shared by the
      # rails-review skill and the AGENTS.md review section so they can't drift.
      def review_partial(name)
        render_template("shared/_rails_review_#{name}.md.tt").strip
      end

      # A template (relative to source_root, or absolute) rendered with ERB in this generator's
      # binding. Read as UTF-8 whatever the locale.
      def render_template(path)
        ERB.new(File.read(File.expand_path(path, self.class.source_root), encoding: "UTF-8"), trim_mode: "-").result(binding)
      end

      def schema_file
        (profile.schema_format == :sql) ? "db/structure.sql" : "db/schema.rb"
      end

      def app_file?(relative)
        File.exist?(File.join(destination_root, relative))
      end

      def test_command
        (profile.test_framework == :rspec) ? "bundle exec rspec" : "bin/rails test"
      end

      def lint_command
        if app_file?("bin/rubocop")
          "bin/rubocop"
        elsif profile.standard? && !app_file?(".rubocop.yml")
          "bundle exec standardrb"
        elsif profile.rubocop?
          "bundle exec rubocop"
        end
      end

      def security_command
        if app_file?("bin/brakeman")
          "bin/brakeman"
        elsif profile.brakeman?
          "bundle exec brakeman"
        end
      end
    end
  end
end
