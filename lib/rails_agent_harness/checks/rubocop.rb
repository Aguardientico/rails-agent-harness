# frozen_string_literal: true

module RailsAgentHarness
  module Checks
    # RuboCop (or Standard) on the changed Ruby files.
    class Rubocop < Base
      check_name "rubocop"

      RUBY_FILE = /(\.(rb|rake|ru|gemspec)|\A(.*\/)?(Gemfile|Rakefile))\z/
      ARGS = %w[--format emacs --force-exclusion --no-color].freeze
      # `path:line:col: C: [Correctable] Cop/Name: message` (emacs formatter).
      OFFENSE = /\A(?<path>.+?):(?<line>\d+):(?<col>\d+): (?<severity>[A-Z]): (?<rest>.*)\z/

      def call
        return skip("disabled in config/agent_harness.yml") unless enabled?
        return skip("no changed Ruby files") if ruby_files.empty?
        return skip("RuboCop not detected") unless profile.rubocop? || configured_command

        result = run(command + ARGS + ruby_files)
        return pass if result.success?

        offenses = result.output.lines.map(&:chomp).filter_map { |line| offense(line) }
        return failure("exit status #{result.exit_status}", tail(result.output)) if offenses.empty?

        failure(pluralize(offenses.size, "offense"), offenses)
      end

      private

      def ruby_files
        @ruby_files ||= files.grep(RUBY_FILE)
      end

      def command
        return configured_command if configured_command
        return ["bin/rubocop"] if executable?("bin/rubocop")
        return %w[bundle exec standardrb] if profile.standard? && !File.exist?(File.join(root, ".rubocop.yml"))

        %w[bundle exec rubocop]
      end

      # The offense line with its path made root-relative (the emacs formatter prints
      # absolute paths).
      def offense(line)
        match = OFFENSE.match(line) or return
        path = match[:path].delete_prefix("#{File.realpath(root)}/").delete_prefix("#{root}/")
        "#{path}:#{match[:line]}:#{match[:col]}: #{match[:severity]}: #{match[:rest]}"
      end
    end
  end
end
