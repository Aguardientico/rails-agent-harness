# frozen_string_literal: true

require "json"

module RailsAgentHarness
  module Checks
    # Brakeman, failing on High and Medium confidence warnings. Brakeman applies
    # config/brakeman.ignore itself.
    class Brakeman < Base
      check_name "brakeman"

      ARGS = %w[--quiet --no-pager --format json --no-exit-on-warn --no-exit-on-error].freeze
      FAILING_CONFIDENCE = %w[High Medium].freeze
      # Only changes here can change Brakeman's findings; anything else skips it to keep hooks fast.
      RELEVANT = %r{\A(app/|config/|lib/|Gemfile\.lock\z)}

      def call
        return skip("disabled in config/agent_harness.yml") unless enabled?
        return skip("Brakeman not detected") unless profile.brakeman? || configured_command
        return skip("no changed files under app/, config/ or lib/") if files.none? { |file| file.match?(RELEVANT) }

        result = run(command + ARGS, separate_stderr: true)
        report = parse(result.stdout)
        return failure("could not read Brakeman's JSON output (exit status #{result.exit_status})", tail(result.output)) unless report

        warnings = report.fetch("warnings", []).select { |warning| FAILING_CONFIDENCE.include?(warning["confidence"]) }
        return pass if warnings.empty?

        details = warnings.map do |warning|
          "#{warning["file"]}:#{warning["line"]} [#{warning["confidence"]}] #{warning["warning_type"]}: #{warning["message"]}"
        end
        failure(pluralize(warnings.size, "warning"), details.sort + error_details(report))
      end

      private

      def command
        return configured_command if configured_command
        return ["bin/brakeman"] if executable?("bin/brakeman")

        %w[bundle exec brakeman]
      end

      # Brakeman prints the JSON report on stdout (stderr is read separately, so warnings
      # printed there can't break parsing).
      def parse(stdout)
        report = JSON.parse(stdout)
        report.is_a?(Hash) ? report : nil
      rescue JSON::ParserError
        nil
      end

      # Files Brakeman couldn't parse (and so didn't scan), shown next to the warnings.
      def error_details(report)
        Array(report["errors"]).map do |error|
          "brakeman error: #{error["error"]}#{" (#{error["location"]})" if error["location"]}"
        end
      end
    end
  end
end
