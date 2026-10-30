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
        unless report
          return failure("could not read Brakeman's JSON output (exit status #{result.exit_status})", tail(result.output))
        end
        # With --no-exit-on-warn/--no-exit-on-error, a non-zero exit means Brakeman itself failed.
        return failure("brakeman exited with status #{result.exit_status}", tail(result.output)) unless result.success?

        warnings = report.fetch("warnings", []).select { |warning| FAILING_CONFIDENCE.include?(warning["confidence"]) }
        errors = scan_errors(report)
        unscanned = errors.select { |error| files.any? { |file| mentions?(error, file) } }
        return pass if warnings.empty? && unscanned.empty?

        details = warnings.map do |warning|
          "#{warning["file"]}:#{warning["line"]} [#{warning["confidence"]}] #{warning["warning_type"]}: #{warning["message"]}"
        end
        summary = [(pluralize(warnings.size, "warning") if warnings.any?), (pluralize(unscanned.size, "changed file") + " not scanned" if unscanned.any?)]
        failure(summary.compact.join(", "), details.sort + errors.map { |error| "brakeman error: #{error}" })
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

      # Messages for files Brakeman couldn't parse, and so didn't scan, such as
      # "app/models/x.rb:3 :: parse error on value ... While processing app/models/x.rb"
      # (`location` is a Brakeman backtrace, not the app file). An error naming a changed file
      # fails the check, since that change wasn't scanned; other errors are only listed, so a
      # pre-existing problem can't trap the agent.
      # Whether `message` names `file` as a whole path, relative or under the root (so
      # lib/a.rb doesn't match app/lib/a.rb). The root may be a symlink (macOS tmp dirs), so
      # its real path is stripped too.
      def mentions?(message, file)
        relative = [root, (File.realpath(root) if File.exist?(root))].compact.uniq.reduce(message) { |text, dir| text.gsub("#{dir}/", "") }
        relative.match?(/(\A|\s)#{Regexp.escape(file)}(:|\s|\z)/)
      end

      def scan_errors(report)
        Array(report["errors"]).filter_map { |error| error["error"].to_s.strip if error.is_a?(Hash) }
      end
    end
  end
end
