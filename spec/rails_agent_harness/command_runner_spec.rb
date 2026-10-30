# frozen_string_literal: true

require "rails_agent_harness/command_runner"

RSpec.describe RailsAgentHarness::CommandRunner do
  let(:runner) { described_class.new(Dir.pwd) }
  let(:script) { 'STDOUT.print "out"; STDOUT.flush; STDERR.print "err"; exit 3' }

  it "captures stdout and stderr together with the exit status and duration" do
    result = runner.call("ruby", "-e", script)

    expect(result.output).to include("out", "err")
    expect(result.stdout).to eq(result.output)
    expect(result.exit_status).to eq(3)
    expect(result.success?).to be(false)
    expect(result.duration).to be >= 0
  end

  it "keeps stdout apart with separate_stderr" do
    result = runner.call("ruby", "-e", script, separate_stderr: true)

    expect(result.stdout).to eq("out")
    expect(result.output).to eq("outerr")
  end

  it "passes arguments without a shell" do
    expect(runner.call("ruby", "-e", "print ARGV.first", "$HOME; echo hi").output).to eq("$HOME; echo hi")
  end

  it "reports a missing executable as exit status 127" do
    result = runner.call("definitely-not-a-command-#{Process.pid}")

    expect(result.exit_status).to eq(127)
    expect(result.output).to include("definitely-not-a-command")
  end
end
