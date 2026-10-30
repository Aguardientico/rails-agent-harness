# frozen_string_literal: true

require "rails_agent_harness/checks"
require "rails_agent_harness/command_runner"

module RailsAgentHarness
  # Runs checks over a set of files and formats the report.
  class Runner
    Report = Data.define(:results, :files, :duration) do
      def failed? = results.any?(&:fail?)

      # The plain-text report: one line when nothing failed; otherwise a header, one block per
      # check and a closing hint. Each check's details are capped at `max_lines` unless verbose.
      def to_s(max_lines:, verbose: false)
        header = "agent-check: #{failed? ? "FAIL" : "PASS"} (#{overview}) - #{files_checked} in #{format("%.1f", duration)}s"
        return header unless failed?

        lines = [header]
        results.each do |result|
          lines << ["[#{result.name}]", result.status.to_s.upcase, result.summary].compact.join(" ")
          lines.concat(truncate(result.details, max_lines, verbose).map { |detail| "  #{detail}" })
        end
        lines << "Fix the issues above, then run bin/agent-check again."
        lines.join("\n")
      end

      private

      def overview
        if failed?
          results.select(&:fail?).map(&:name).join(", ")
        else
          results.map { |result| result.skip? ? "#{result.name} skipped: #{result.summary}" : result.name }.join(", ")
        end
      end

      def files_checked
        "#{files.size} #{(files.size == 1) ? "file" : "files"} checked"
      end

      def truncate(details, max_lines, verbose)
        return details if verbose || details.size <= max_lines

        details.first(max_lines) + ["... #{details.size - max_lines} more lines (run bin/agent-check --verbose)"]
      end
    end

    def initialize(root:, config:, profile:, files:, checks: Checks.registry, runner: CommandRunner.new(root))
      @root = root
      @config = config
      @profile = profile
      @files = files
      @checks = checks
      @runner = runner
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = @checks.map do |check|
        check.new(root: @root, config: @config, profile: @profile, files: @files, runner: @runner).call
      end
      Report.new(results: results, files: @files, duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end
  end
end
