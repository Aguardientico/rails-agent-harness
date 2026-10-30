# frozen_string_literal: true

require "shellwords"

module RailsAgentHarness
  module Checks
    # A check gets the project root, the loaded Configuration, the AppProfile, the files to
    # look at (root-relative), a CommandRunner and, when known, the files added since the merge
    # base (`added`, nil otherwise), and returns a CheckResult from #call.
    class Base
      class << self
        # The check's name in output, `--only` and config/agent_harness.yml. (Not `name`,
        # which would shadow Module#name.)
        def check_name(value = nil)
          value ? @check_name = value : @check_name
        end
      end

      attr_reader :root, :config, :profile, :files, :runner, :added

      def initialize(root:, config:, profile:, files:, runner:, added: nil)
        @root = root.to_s
        @config = config
        @profile = profile
        @files = files
        @runner = runner
        @added = added
      end

      def name = self.class.check_name

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def pass(summary = nil, details = []) = result(:pass, summary, details)

      def failure(summary, details = []) = result(:fail, summary, details)

      def skip(summary) = result(:skip, summary, [])

      def result(status, summary, details)
        CheckResult.new(name: name, status: status, summary: summary, details: details)
      end

      def enabled?
        config.check_enabled?(name)
      end

      def configured_command
        command = config.check_command(name)
        command && Shellwords.split(command)
      end

      def executable?(relative)
        path = File.join(root, relative)
        File.file?(path) && File.executable?(path)
      end

      def run(argv, **options)
        runner.call(*argv, **options)
      end

      # The last `count` non-blank lines of command output.
      def tail(output, count = config.max_output_lines)
        output.lines.map(&:rstrip).reject(&:empty?).last(count)
      end

      def pluralize(count, word)
        "#{count} #{word}#{"s" unless count == 1}"
      end
    end
  end
end
