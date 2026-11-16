# frozen_string_literal: true

require "erb"
require "digest"
require "json"
require "rails/generators"
require "rails_agent_harness"
require "rails_agent_harness/app_detector"
require "rails_agent_harness/installation"

module AgentHarness
  module Generators
    class InstallGenerator < Rails::Generators::Base
      BEGIN_MARKER = "<!-- BEGIN rails_agent_harness -->"
      END_MARKER = "<!-- END rails_agent_harness -->"
      MARKED_BLOCK = /#{Regexp.escape(BEGIN_MARKER)}.*?#{Regexp.escape(END_MARKER)}\n?/m
      MARKER = /#{Regexp.escape(BEGIN_MARKER)}|#{Regexp.escape(END_MARKER)}/

      # Our Claude Code hook entries, by event. The command identifies an entry when merging.
      CLAUDE_HOOKS = JSON.parse(File.read(File.expand_path("templates/clients.json", __dir__))).fetch("claude_hooks").freeze

      # .gitignore lines that already ignore the root .claude/settings.local.json. The last one is
      # what Claude Code adds to the global git excludes when it creates the file itself.
      CLAUDE_LOCAL_SETTINGS_RULES = %w[
        .claude/settings.local.json /.claude/settings.local.json **/.claude/settings.local.json
      ].freeze
      CLAUDE_SETTINGS_SCHEMA = "https://json.schemastore.org/claude-code-settings.json"
      CLAUDE_MD_HINTS = {
        "CLAUDE.md" => "add @AGENTS.md to it or delete it",
        ".claude/CLAUDE.md" => "add @../AGENTS.md to it or delete it",
        "CLAUDE.local.md" => "add @AGENTS.md to it, or set Project instructions to claude-md-and-agents-md in /config"
      }.freeze

      source_root File.expand_path("templates", __dir__)

      desc "Writes AGENTS.md, config/agent_harness.yml and bin/agent-check tuned to this app's stack, " \
        "wires native client hooks and portable skills, and adds /.claude/settings.local.json to " \
        ".gitignore. Never touches CLAUDE.md."

      class_option :skip_claude_hooks, type: :boolean, default: false,
        desc: "Don't add bin/agent-check hooks to .claude/settings.json"
      class_option :skip_skills, type: :boolean, default: false,
        desc: "Don't write client rails-review skills"
      class_option :force_client_files, type: :boolean, default: false,
        desc: "Replace generated skills and Aider config without overwriting agent_harness.yml"
      class_option :skip_client_hooks, type: :boolean, default: false,
        desc: "Don't add Codex, Copilot, Cursor or Gemini hooks"

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

      def note_claude_md
        CLAUDE_MD_HINTS.each do |path, hint|
          next if !app_file?(path) || File.identical?(File.join(destination_root, path), File.join(destination_root, "AGENTS.md"))

          say_status :note, "#{path} left untouched; while it exists Claude Code reads it instead of AGENTS.md, so #{hint}", :yellow
        end
      end

      def create_agent_check_binstub
        template "bin/agent-check.tt", "bin/agent-check"
        chmod "bin/agent-check", 0o755
      end

      def configure_claude_hooks
        return if options[:skip_claude_hooks]

        merge_claude_hooks(CLAUDE_HOOKS)
      end

      def ignore_claude_local_settings
        path = ".gitignore"
        full_path = File.join(destination_root, path)
        existing = File.exist?(full_path) ? File.read(full_path, encoding: "UTF-8") : ""
        # In .gitignore the last matching line wins, so a later "!rule" re-includes the file.
        last_match = existing.lines.map(&:strip).reverse.find do |line|
          CLAUDE_LOCAL_SETTINGS_RULES.include?(line.delete_prefix("!"))
        end
        if last_match && !last_match.start_with?("!")
          return say_status(:identical, path, :blue)
        end

        separator = (existing.empty? || existing.end_with?("\n")) ? "" : "\n"
        create_file path, "#{existing}#{separator}/.claude/settings.local.json\n", force: true
      end

      # The skill is fully owned by the gem (no markers): an existing, different file is kept
      # unless --force, without Thor's interactive prompt (which overwrites on EOF, e.g. when an
      # agent runs the generator).
      def create_review_skill
        return if options[:skip_skills]

        client_manifest.fetch("skills").each do |path|
          write_owned_file(path, render_template("skills/rails-review/SKILL.md.tt"))
        end
      end

      def configure_clients
        instruction_paths.each { |path| upsert_marked_block(path, agents_md) }
        unless options[:skip_client_hooks]
          client_manifest.fetch("clients").each_value do |client|
            merge_client_config(client.fetch("path"), client.fetch("config"))
          end
        end
        return if problems.any?

        client_manifest.fetch("owned_files").each { |path, content| write_owned_file(path, content) }
        return if options[:pretend]

        files = client_manifest.fetch("owned_files").transform_values { |content| Digest::SHA256.hexdigest(content) }
        files["bin/agent-check"] = Digest::SHA256.hexdigest(render_template("bin/agent-check.tt"))
        unless options[:skip_skills]
          digest = Digest::SHA256.hexdigest(render_template("skills/rails-review/SKILL.md.tt"))
          client_manifest.fetch("skills").each { |path| files[path] = digest }
        end
        instructions = (instruction_paths + ["AGENTS.md"]).to_h do |path|
          [path, RailsAgentHarness::Installation.instruction_digest(File.read(File.join(destination_root, path), encoding: "UTF-8"))]
        end
        hooks = {}
        unless options[:skip_client_hooks]
          client_manifest.fetch("clients").each_value do |client|
            hooks[client.fetch("path")] = client.fetch("config").fetch("hooks").transform_values { |groups| groups.flat_map { |group| client_commands(group) } }
          end
        end
        unless options[:skip_claude_hooks]
          hooks[".claude/settings.json"] = CLAUDE_HOOKS.transform_values do |group|
            [group.fetch("hooks").first.fetch("command")[%r{bin/agent-check hook [\w-]+}]]
          end
        end
        contents = {"version" => 1, "files" => files, "instructions" => instructions, "hooks" => hooks, "required" => ["config/agent_harness.yml"]}
        create_file "config/agent_harness_clients.json", JSON.pretty_generate(contents) + "\n", force: true
        problems.concat(RailsAgentHarness::Installation.verify(destination_root))
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

      def client_manifest
        @client_manifest ||= JSON.parse(File.read(File.join(self.class.source_root, "clients.json")))
      end

      def write_owned_file(path, content)
        full_path = File.join(destination_root, path)
        if File.exist?(full_path) && File.read(full_path, encoding: "UTF-8") != content && !options[:force] && !options[:force_client_files]
          return say_status(:exists, "#{path} (differs; kept, use --force-client-files to overwrite)", :blue)
        end
        create_file path, content, force: true
      end

      def merge_client_config(path, additions)
        full_path = File.join(destination_root, path)
        settings = File.exist?(full_path) ? JSON.parse(File.read(full_path, encoding: "UTF-8")) : {}
        original = JSON.generate(settings)
        valid = settings.is_a?(Hash) && (!settings.key?("hooks") || settings["hooks"].is_a?(Hash)) &&
          additions.fetch("hooks").keys.all? { |event| !settings.fetch("hooks", {}).key?(event) || settings["hooks"][event].is_a?(Array) } &&
          (!additions.key?("version") || !settings.key?("version") || settings["version"] == additions["version"])
        unless valid
          raise ArgumentError, "unexpected hook configuration structure"
        end
        additions.each { |key, value| settings[key] ||= value unless key == "hooks" }
        hooks = settings["hooks"] ||= {}
        additions.fetch("hooks").each do |event, entries|
          hooks[event] ||= []
          entries.each do |entry|
            commands = client_commands(entry)
            hooks[event] << entry unless hooks[event].any? { |existing| (client_commands(existing) & commands).any? }
          end
        end
        return say_status(:identical, path, :blue) if File.exist?(full_path) && JSON.generate(settings) == original

        create_file path, JSON.pretty_generate(settings) + "\n", force: true
      rescue JSON::ParserError, ArgumentError
        problems << "#{path}: invalid JSON or hook configuration structure; file left untouched"
      end

      def instruction_paths
        client_manifest.fetch("instructions") + client_manifest.fetch("optional_instructions").select { |path| app_file?(path) }
      end

      def client_commands(group)
        RailsAgentHarness::Installation.commands(group)
      end

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
        files = ["AGENTS.md", "config/agent_harness.yml", "bin/agent-check", ".gitignore"]
        files << ".claude/settings.json" unless options[:skip_claude_hooks]
        files += client_manifest.fetch("skills") unless options[:skip_skills]
        files += instruction_paths + ["config/agent_harness_clients.json", ".aider.agent-harness.yml"]
        files += client_manifest.fetch("clients").values.map { |client| client.fetch("path") } unless options[:skip_client_hooks]
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

        migrated = false
        entries.each do |event, entry|
          command = entry.fetch("hooks").first.fetch("command")
          legacy = command[/"\$\{CLAUDE_PROJECT_DIR\}"\/bin\/agent-check hook [\w-]+/]
          hooks[event].each do |group|
            next unless group.is_a?(Hash) && group["hooks"].is_a?(Array)

            group["hooks"].each do |hook|
              next unless hook.is_a?(Hash) && hook["command"] == legacy

              hook["command"] = command
              migrated = true
            end
          end
        end
        added = entries.reject { |event, entry| hook_command?(hooks[event], entry) }
        return say_status(:identical, path, :blue) if added.empty? && !migrated

        added.each { |event, entry| hooks[event] << entry }
        create_file path, "#{JSON.pretty_generate(settings)}\n", force: true
      rescue JSON::ParserError
        problems << "#{path}: invalid JSON; add the bin/agent-check hooks by hand"
        say_status :error, "#{path} is not valid JSON; add the bin/agent-check hooks by hand", :red
      end

      # Whether any hook in `groups` already runs the `bin/agent-check hook <event>` of `entry`.
      def hook_command?(groups, entry)
        signature = entry["hooks"].first["command"][%r{bin/agent-check hook [\w-]+}]
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
