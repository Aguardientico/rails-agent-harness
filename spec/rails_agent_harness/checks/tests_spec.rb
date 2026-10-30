# frozen_string_literal: true

require "rails_agent_harness/checks"

RSpec.describe RailsAgentHarness::Checks::Tests do
  around do |example|
    Dir.mktmpdir("agent_harness_tests") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  let(:runner) { AgentCheckHelper::FakeRunner.new }
  let(:config) { load_config(root) }

  def check(files, runner: self.runner, profile: build_profile, config: self.config)
    described_class.new(root: root, config: config, profile: profile, files: files, runner: runner).call
  end

  describe ".map" do
    def map(files, framework)
      described_class.map(files, framework: framework, root: root)
    end

    it "maps changed files to RSpec specs that exist" do
      %w[
        spec/models/post_spec.rb spec/models/comment_spec.rb spec/controllers/posts_controller_spec.rb
        spec/requests/posts_spec.rb spec/requests/admin/users_spec.rb spec/lib/importer_spec.rb
        spec/jobs/sync_job_spec.rb
      ].each { |spec| touch(root, spec) }

      expect(map(%w[spec/models/comment_spec.rb], :rspec)).to eq(%w[spec/models/comment_spec.rb])
      expect(map(%w[app/models/post.rb], :rspec)).to eq(%w[spec/models/post_spec.rb])
      expect(map(%w[app/jobs/sync_job.rb], :rspec)).to eq(%w[spec/jobs/sync_job_spec.rb])
      expect(map(%w[app/controllers/posts_controller.rb], :rspec)).to eq(%w[spec/controllers/posts_controller_spec.rb spec/requests/posts_spec.rb])
      expect(map(%w[app/views/posts/index.html.erb app/views/posts/_form.html.erb], :rspec)).to eq(%w[spec/requests/posts_spec.rb])
      expect(map(%w[app/views/admin/users/show.html.erb], :rspec)).to eq(%w[spec/requests/admin/users_spec.rb])
      expect(map(%w[lib/importer.rb], :rspec)).to eq(%w[spec/lib/importer_spec.rb])
    end

    it "maps changed files to Minitest tests that exist" do
      %w[
        test/models/post_test.rb test/controllers/posts_controller_test.rb test/integration/posts_test.rb
        test/lib/importer_test.rb
      ].each { |test| touch(root, test) }

      expect(map(%w[test/models/post_test.rb], :minitest)).to eq(%w[test/models/post_test.rb])
      expect(map(%w[app/models/post.rb], :minitest)).to eq(%w[test/models/post_test.rb])
      expect(map(%w[app/controllers/posts_controller.rb], :minitest)).to eq(%w[test/controllers/posts_controller_test.rb test/integration/posts_test.rb])
      expect(map(%w[app/views/posts/index.html.erb], :minitest)).to eq(%w[test/controllers/posts_controller_test.rb])
      expect(map(%w[lib/importer.rb], :minitest)).to eq(%w[test/lib/importer_test.rb])
    end

    it "maps nothing for migrations, schema, routes and config, or when the test file is missing" do
      touch(root, "spec/models/post_spec.rb")

      expect(map(%w[db/migrate/20261030000000_x.rb db/schema.rb config/routes.rb config/application.rb], :rspec)).to eq([])
      expect(map(%w[app/models/comment.rb], :rspec)).to eq([])
    end

    it "deduplicates" do
      touch(root, "spec/models/post_spec.rb")

      expect(map(%w[app/models/post.rb spec/models/post_spec.rb], :rspec)).to eq(%w[spec/models/post_spec.rb])
    end
  end

  it "runs the mapped specs with bundle exec rspec" do
    touch(root, "spec/models/post_spec.rb")
    result = check(%w[app/models/post.rb])

    expect(result).to have_attributes(status: :pass, summary: "1 test file")
    expect(runner.calls).to eq([%w[bundle exec rspec spec/models/post_spec.rb]])
  end

  it "prefers an executable bin/rspec" do
    touch(root, "spec/models/post_spec.rb")
    touch(root, "bin/rspec", executable: true)
    check(%w[app/models/post.rb])

    expect(runner.calls).to eq([%w[bin/rspec spec/models/post_spec.rb]])
  end

  it "runs Minitest with bin/rails test" do
    touch(root, "test/models/post_test.rb")
    check(%w[app/models/post.rb], profile: build_profile(test_framework: :minitest))

    expect(runner.calls).to eq([%w[bin/rails test test/models/post_test.rb]])
  end

  it "uses a configured command" do
    touch(root, "spec/models/post_spec.rb")
    check(%w[app/models/post.rb], config: load_config(root, "checks:\n  tests:\n    command: bin/turbo_tests -n 2\n"))

    expect(runner.calls).to eq([%w[bin/turbo_tests -n 2 spec/models/post_spec.rb]])
  end

  it "reports RSpec failures" do
    touch(root, "spec/models/post_spec.rb")
    output = <<~OUT
      F.

      Failures:
        1) Post validates title
           Failure/Error: expect(post).to be_valid

      2 examples, 1 failure

      Failed examples:

      rspec ./spec/models/post_spec.rb:12 # Post validates title
    OUT
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output, exit_status: 1))

    expect(result).to have_attributes(status: :fail, summary: "1 failure", details: ["rspec ./spec/models/post_spec.rb:12 # Post validates title"])
  end

  it "reports Minitest failures and errors with their locations" do
    touch(root, "test/models/post_test.rb")
    output = <<~OUT
      Running 2 tests in a single process
      F

      Failure:
      PostTest#test_title [test/models/post_test.rb:5]:
      Expected false to be truthy.


      bin/rails test test/models/post_test.rb:4

      E

      Error:
      PostTest#test_boom:
      RuntimeError: boom
          test/models/post_test.rb:9:in 'block in <class:PostTest>'


      bin/rails test test/models/post_test.rb:8

      2 runs, 1 assertions, 1 failures, 1 errors, 0 skips
    OUT
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output, exit_status: 1),
      profile: build_profile(test_framework: :minitest))

    expect(result).to have_attributes(status: :fail, summary: "2 failures")
    expect(result.details).to eq([
      "Failure: PostTest#test_title [test/models/post_test.rb:5]",
      "Error: PostTest#test_boom [test/models/post_test.rb:8]"
    ])
  end

  it "falls back to the last max_output_lines lines when no failure lines are found" do
    touch(root, "spec/models/post_spec.rb")
    output = (1..60).map { |n| "line #{n}" }.join("\n")
    result = check(%w[app/models/post.rb], runner: AgentCheckHelper::FakeRunner.new(output: output, exit_status: 1),
      config: load_config(root, "max_output_lines: 3\n"))

    expect(result).to have_attributes(status: :fail, summary: "exit status 1", details: ["line 58", "line 59", "line 60"])
  end

  describe "skipping" do
    it "skips when disabled" do
      expect(check(%w[app/models/post.rb], config: load_config(root, "checks:\n  tests:\n    enabled: false\n")).status).to eq(:skip)
    end

    it "skips without a test framework unless a command is configured" do
      touch(root, "test/models/post_test.rb")

      expect(check(%w[app/models/post.rb], profile: build_profile(test_framework: :none)).summary).to eq("no test framework detected")

      config = load_config(root, "checks:\n  tests:\n    command: bin/my-tests\n")
      check(%w[app/models/post.rb], profile: build_profile(test_framework: :none), config: config)
      expect(runner.calls).to eq([%w[bin/my-tests test/models/post_test.rb]])
    end

    it "skips when no tests are mapped" do
      result = check(%w[app/models/post.rb])

      expect(result).to have_attributes(status: :skip, summary: "no tests mapped to changed files")
      expect(runner.calls).to be_empty
    end
  end
end
