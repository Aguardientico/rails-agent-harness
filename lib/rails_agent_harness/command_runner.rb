# frozen_string_literal: true

require "open3"

module RailsAgentHarness
  # Runs a command (an argv array, never a shell string) in the project root and captures
  # stdout and stderr together. Checks receive it by injection so specs can pass a fake.
  class CommandRunner
    # `output` is stdout and stderr together; `stdout` is stdout alone when the command was run
    # with `separate_stderr: true`, else the same as `output`.
    Result = Data.define(:output, :exit_status, :duration, :stdout) do
      def initialize(output:, exit_status:, duration:, stdout: output)
        super
      end

      def success? = exit_status == 0
    end

    def initialize(root)
      @root = root.to_s
    end

    def call(*argv, separate_stderr: false)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if separate_stderr
        stdout, stderr, status = Open3.capture3(*argv, chdir: @root)
        output = stdout + stderr
      else
        output, status = Open3.capture2e(*argv, chdir: @root)
        stdout = output
      end
      Result.new(output: output, exit_status: status.exitstatus || 1, duration: elapsed(started), stdout: stdout)
    rescue SystemCallError => e
      Result.new(output: "#{argv.first}: #{e.message}", exit_status: 127, duration: elapsed(started))
    end

    private

    def elapsed(started)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
  end
end
