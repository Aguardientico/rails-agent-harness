# frozen_string_literal: true

require "open3"

module RailsAgentHarness
  # Runs a command (an argv array, never a shell string) in the project root and captures
  # stdout and stderr together. Checks receive it by injection so specs can pass a fake.
  class CommandRunner
    Result = Data.define(:output, :exit_status, :duration) do
      def success? = exit_status == 0
    end

    def initialize(root)
      @root = root.to_s
    end

    def call(*argv)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = Open3.capture2e(*argv, chdir: @root)
      Result.new(output: output, exit_status: status.exitstatus || 1, duration: elapsed(started))
    rescue SystemCallError => e
      Result.new(output: "#{argv.first}: #{e.message}", exit_status: 127, duration: elapsed(started))
    end

    private

    def elapsed(started)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
  end
end
