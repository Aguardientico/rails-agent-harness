# frozen_string_literal: true

require "rails_agent_harness/runner"

RSpec.describe RailsAgentHarness::Runner do
  def result(name, status, summary = nil, details = [])
    RailsAgentHarness::CheckResult.new(name: name, status: status, summary: summary, details: details)
  end

  def report(results, files: %w[a.rb b.rb c.rb], duration: 4.21)
    described_class::Report.new(results: results, files: files, duration: duration)
  end

  it "runs each check with the same inputs and collects the results" do
    seen = []
    check = Class.new(RailsAgentHarness::Checks::Base) do
      check_name "spy"
      define_method(:call) do
        seen << [root, files, runner]
        pass("ok")
      end
    end
    runner = AgentCheckHelper::FakeRunner.new

    report = described_class.new(root: "/app", config: nil, profile: nil, files: %w[x.rb], checks: [check, check], runner: runner).call

    expect(report.results.map(&:status)).to eq(%i[pass pass])
    expect(seen).to eq([["/app", %w[x.rb], runner]] * 2)
    expect(report.failed?).to be(false)
  end

  describe "report" do
    it "is one line when nothing failed" do
      text = report([result("rubocop", :pass), result("brakeman", :pass), result("tests", :skip, "no tests mapped to changed files")]).to_s(max_lines: 40)

      expect(text).to eq("agent-check: PASS (rubocop, brakeman, tests skipped: no tests mapped to changed files) - 3 files checked in 4.2s")
    end

    it "lists every check with details and a closing hint when something failed" do
      text = report([
        result("rubocop", :fail, "2 offenses", ["app/models/post.rb:3:5: C: Style/StringLiterals: Prefer double-quoted strings."]),
        result("brakeman", :pass),
        result("tests", :fail, "1 failure", ["rspec ./spec/models/post_spec.rb:12 # Post validates title"])
      ], files: %w[a.rb]).to_s(max_lines: 40)

      expect(text).to eq(<<~TEXT.chomp)
        agent-check: FAIL (rubocop, tests) - 1 file checked in 4.2s
        [rubocop] FAIL 2 offenses
          app/models/post.rb:3:5: C: Style/StringLiterals: Prefer double-quoted strings.
        [brakeman] PASS
        [tests] FAIL 1 failure
          rspec ./spec/models/post_spec.rb:12 # Post validates title
        Fix the issues above, then run bin/agent-check again.
      TEXT
    end

    it "truncates each check's details to max_lines unless verbose" do
      failed = report([result("rubocop", :fail, "5 offenses", %w[l1 l2 l3 l4 l5])])

      expect(failed.to_s(max_lines: 2).lines.map(&:chomp)).to include("  l1", "  l2", "  ... 3 more lines (run bin/agent-check --verbose)")
      expect(failed.to_s(max_lines: 2)).not_to include("l3")
      expect(failed.to_s(max_lines: 2, verbose: true)).to include("l5")
    end

    it "contains no ANSI escape codes" do
      text = report([result("rubocop", :fail, "1 offense", ["x"])]).to_s(max_lines: 40)

      expect(text).not_to match(/\e\[/)
    end
  end
end
