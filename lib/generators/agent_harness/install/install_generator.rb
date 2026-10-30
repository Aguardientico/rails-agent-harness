# frozen_string_literal: true

require "erb"
require "rails/generators"
require "rails_agent_harness"
require "rails_agent_harness/app_detector"

module AgentHarness
  module Generators
    class InstallGenerator < Rails::Generators::Base
      BEGIN_MARKER = "<!-- BEGIN rails_agent_harness -->"
      END_MARKER = "<!-- END rails_agent_harness -->"
      MARKED_BLOCK = /#{Regexp.escape(BEGIN_MARKER)}.*?#{Regexp.escape(END_MARKER)}\n?/m

      source_root File.expand_path("templates", __dir__)

      desc "Writes AGENTS.md, CLAUDE.md and config/agent_harness.yml tuned to this app's stack."

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
        upsert_marked_block "CLAUDE.md", <<~MARKDOWN
          @AGENTS.md

          This project's agent instructions live in AGENTS.md (shared by Claude Code, Codex and Cursor). Read it before making changes.
        MARKDOWN
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
        say "Next steps:"
        say "  1. Review AGENTS.md and config/agent_harness.yml."
        say "  2. Commit AGENTS.md, CLAUDE.md and config/agent_harness.yml."
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
          ERB.new(File.read(partial), trim_mode: "-").result(binding).strip
        end.join("\n\n")
      end

      # Writes `content` between BEGIN/END markers in `path`: creates the file, appends the block
      # to a file without markers (keeping the user's content), or replaces only the existing
      # block. Unchanged content is left alone, so re-running is idempotent.
      def upsert_marked_block(path, content)
        block = "#{BEGIN_MARKER}\n#{content.strip}\n#{END_MARKER}\n"
        full_path = File.join(destination_root, path)
        return create_file(path, block) unless File.exist?(full_path)

        existing = File.read(full_path)
        updated =
          if existing.include?(BEGIN_MARKER)
            unless existing.match?(MARKED_BLOCK)
              return say_status(:error, "#{path} has #{BEGIN_MARKER} but no #{END_MARKER}; fix it and re-run", :red)
            end
            existing.sub(MARKED_BLOCK) { block }
          elsif existing.strip.empty?
            block
          else
            "#{existing.rstrip}\n\n#{block}"
          end

        if updated == existing
          say_status :identical, path, :blue
        else
          create_file path, updated, force: true
        end
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
