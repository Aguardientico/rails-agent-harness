# frozen_string_literal: true

module RailsAgentHarness
  module Checks
    # Runs the tests mapped to the changed files.
    #
    # | Changed file                           | RSpec                            | Minitest                                       |
    # |----------------------------------------|----------------------------------|------------------------------------------------|
    # | spec/**/*_spec.rb / test/**/*_test.rb  | itself                           | itself                                         |
    # | app/<dir>/<path>.rb                    | spec/<dir>/<path>_spec.rb        | test/<dir>/<path>_test.rb                      |
    # | app/controllers/<path>_controller.rb   | also spec/requests/<path>_spec.rb | also test/integration/<path>_test.rb          |
    # | app/views/<resource>/**                | spec/requests/<resource>_spec.rb | test/controllers/<resource>_controller_test.rb |
    # | lib/<path>.rb                          | spec/lib/<path>_spec.rb          | test/lib/<path>_test.rb                        |
    # | anything else (migrations, config, ...) | none                            | none                                           |
    #
    # Only test files that exist are kept, without duplicates.
    class Tests < Base
      check_name "tests"

      # `rspec ./spec/models/post_spec.rb:12 # Post validates title`
      RSPEC_FAILURE = %r{\Arspec \./\S+:\d+}
      RSPEC_SUMMARY = /\d+ examples?, (\d+) failures?/
      # Rails' Minitest reporter prints `Failure:`/`Error:` followed by the test name and,
      # for failures, `[file:line]`.
      MINITEST_HEADER = /\A(Failure|Error):\z/
      MINITEST_RERUN = %r{\Abin/rails test \S+:\d+\z}

      def self.map(files, framework:, root:)
        mapped = files.flat_map { |file| candidates(file, framework) }
        mapped.uniq.select { |path| File.file?(File.join(root.to_s, path)) }
      end

      def self.candidates(file, framework)
        rspec = framework == :rspec
        case file
        when %r{\Aspec/.+_spec\.rb\z}, %r{\Atest/.+_test\.rb\z}
          [file]
        when %r{\Aapp/views/(.+)/[^/]+\z}
          rspec ? ["spec/requests/#{$1}_spec.rb"] : ["test/controllers/#{$1}_controller_test.rb"]
        when %r{\Aapp/controllers/(.+)_controller\.rb\z}
          path = $1
          rspec ? ["spec/controllers/#{path}_controller_spec.rb", "spec/requests/#{path}_spec.rb"] : ["test/controllers/#{path}_controller_test.rb", "test/integration/#{path}_test.rb"]
        when %r{\Aapp/(.+)\.rb\z}
          rspec ? ["spec/#{$1}_spec.rb"] : ["test/#{$1}_test.rb"]
        when %r{\Alib/(.+)\.rb\z}
          rspec ? ["spec/lib/#{$1}_spec.rb"] : ["test/lib/#{$1}_test.rb"]
        else
          []
        end
      end

      def call
        return skip("disabled in config/agent_harness.yml") unless enabled?
        return skip("no test framework detected") if profile.test_framework == :none && !configured_command

        tests = self.class.map(files, framework: framework, root: root)
        return skip("no tests mapped to changed files") if tests.empty?

        result = run(command + tests)
        return pass(pluralize(tests.size, "test file")) if result.success?

        details = (framework == :rspec) ? rspec_failures(result.output) : minitest_failures(result.output)
        return failure("exit status #{result.exit_status}", tail(result.output)) if details.empty?

        failure(pluralize(details.size, "failure"), details)
      end

      private

      # The detected framework; with a custom command but no detected framework, guess from
      # the directories present.
      def framework
        return profile.test_framework unless profile.test_framework == :none

        File.directory?(File.join(root, "spec")) ? :rspec : :minitest
      end

      def command
        return configured_command if configured_command
        return ["bin/rails", "test"] if framework == :minitest
        return ["bin/rspec"] if executable?("bin/rspec")

        %w[bundle exec rspec]
      end

      def rspec_failures(output)
        output.lines.map(&:strip).grep(RSPEC_FAILURE)
      end

      # "Failure: PostTest#test_title [test/models/post_test.rb:5]". Errors carry no location
      # on the name line, so it comes from the rerun line Rails prints after each failure
      # (`bin/rails test test/models/post_test.rb:8`).
      def minitest_failures(output)
        lines = output.lines.map(&:strip)
        lines.each_with_index.filter_map do |line, index|
          next unless line.match?(MINITEST_HEADER)

          test = lines[index + 1].to_s.delete_suffix(":")
          location = test[/\[(.+?)\]\z/, 1] || lines[(index + 2)..].find { |rest| rest.match?(MINITEST_RERUN) }&.split&.last
          test = test.sub(/\s*\[.+?\]\z/, "")
          location ? "#{line} #{test} [#{location}]" : "#{line} #{test}"
        end
      end
    end
  end
end
