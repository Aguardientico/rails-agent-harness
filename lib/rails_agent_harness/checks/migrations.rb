# frozen_string_literal: true

require "rails_agent_harness/changed_files"
require "rails_agent_harness/guards/migration_guard"

module RailsAgentHarness
  module Checks
    # The migration/schema guard's heuristic rules (see Guards::MigrationGuard), for agents
    # without hooks. `guards.migrations` and `guards.schema` toggle their rules independently.
    class Migrations < Base
      check_name "migrations"

      def call
        unless config.guard_enabled?(:migrations) || config.guard_enabled?(:schema)
          return skip("guards disabled in config/agent_harness.yml")
        end
        if files.none? { |file| Guards::MigrationGuard.migration?(file) || Guards::MigrationGuard.schema?(file) }
          return skip("no migration or schema changes")
        end

        problems = guard.problems(files: files, added: added_files, schema_format: profile.schema_format)
        problems.empty? ? pass : failure(pluralize(problems.size, "problem"), problems)
      end

      private

      def guard
        Guards::MigrationGuard.new(root: root, config: config)
      end

      # Files added since the merge base. The CLI passes them; otherwise (e.g. `--files`) ask
      # git, and outside a git repository treat every file given as added.
      def added_files
        return added & files if added

        ChangedFiles.new(root, base_branch: config.base_branch).added & files
      rescue Error
        files
      end
    end
  end
end
