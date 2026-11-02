# frozen_string_literal: true

require "yaml"

RSpec.describe ".github/workflows/ci.yml" do
  subject(:workflow) { YAML.load_file(File.join(DummyAppHelper::GEM_ROOT, ".github/workflows/ci.yml")) }

  let(:triggers) { workflow.fetch(true) }
  let(:test_job) { workflow["jobs"]["test"] }

  def expand_matrix(matrix)
    axes = matrix.except("include", "exclude")
    jobs = axes.values.first.product(*axes.values.drop(1)).map { |combo| axes.keys.zip(combo).to_h }
    jobs + matrix.fetch("include", []).reject do |extra|
      jobs.any? { |job| extra.all? { |key, value| job[key] == value } }
    end
  end

  it "runs on pushes to main and on pull requests" do
    expect(triggers["push"]).to eq("branches" => ["main"])
    expect(triggers).to have_key("pull_request")
  end

  it "gives the workflow token read-only access" do
    expect(workflow["permissions"]).to eq("contents" => "read")
  end

  it "cancels superseded pull request builds but not pushes to main" do
    expect(workflow["concurrency"]).to eq(
      "group" => "${{ github.workflow }}-${{ github.ref }}",
      "cancel-in-progress" => "${{ github.event_name == 'pull_request' }}"
    )
  end

  it "pins the latest Ruby to 4.0.9 in .ruby-version" do
    expect(File.read(File.join(DummyAppHelper::GEM_ROOT, ".ruby-version")).strip).to eq("4.0.9")
  end

  it "lints with standardrb on the latest Ruby" do
    lint = workflow["jobs"]["lint"]
    setup = lint["steps"].find { |step| step["uses"] == "ruby/setup-ruby@v1" }

    expect(setup["with"]).to include("ruby-version" => ".ruby-version", "bundler-cache" => true)
    expect(lint["steps"].map { |step| step["run"] }).to include("bundle exec standardrb")
  end

  it "tests Ruby 3.3/3.4/4.0 on Rails main and 8.1, all required" do
    jobs = expand_matrix(test_job["strategy"]["matrix"])

    expect(test_job["strategy"]["fail-fast"]).to be(false)
    expect(jobs).to contain_exactly(
      {"ruby" => "3.3", "rails" => "main"},
      {"ruby" => "3.4", "rails" => "main"},
      {"ruby" => "4.0", "rails" => "main"},
      {"ruby" => "3.3", "rails" => "8.1"},
      {"ruby" => "3.4", "rails" => "8.1"},
      {"ruby" => "4.0", "rails" => "8.1"}
    )
    expect(test_job).not_to have_key("continue-on-error")
    expect(test_job["env"]).to eq("RAILS_VERSION" => "${{ matrix.rails }}")
    expect(test_job["name"]).to start_with("Ruby ${{ matrix.ruby }} / Rails ${{ matrix.rails }}")
    expect(test_job["steps"].map { |step| step["run"] }).to include("bundle exec rspec")
  end

  it "runs the demo on the latest Ruby / Rails main" do
    demo = workflow["jobs"]["demo"]
    setup = demo["steps"].find { |step| step["uses"] == "ruby/setup-ruby@v1" }

    expect(demo["env"]).to eq("RAILS_VERSION" => "main")
    expect(setup["with"]).to include("ruby-version" => ".ruby-version", "bundler-cache" => true)
    expect(demo["steps"].map { |step| step["run"] }).to include("demo/run")
  end

  it "builds the gem and checks its file list" do
    steps = workflow["jobs"]["build"]["steps"]
    run = ->(name) { steps.find { |step| step["name"] == name }.fetch("run") }

    expect(steps.map { |step| step["run"] }).to include("gem build rails_agent_harness.gemspec", "tar -xOf rails_agent_harness-*.gem data.tar.gz | tar -tz")
    expect(run["Only lib/**, LICENSE.txt, README.md and CHANGELOG.md are packaged"]).to include("grep -vE '^(lib/|LICENSE.txt$|README.md$|CHANGELOG.md$)'")
    expect(run["Every tracked lib/ file, LICENSE.txt, README.md and CHANGELOG.md is packaged"]).to eq(
      "! comm -23 <(git ls-files lib LICENSE.txt README.md CHANGELOG.md | sort) <(tar -xOf rails_agent_harness-*.gem data.tar.gz | tar -tz | sort) | grep ."
    )
  end

  it "installs the packaged gem into a fresh Rails main app on the latest Ruby" do
    smoke = workflow["jobs"]["smoke"]
    setup = smoke["steps"].find { |step| step["uses"] == "ruby/setup-ruby@v1" }

    expect(smoke["env"]).to eq("RAILS_VERSION" => "main")
    expect(setup["with"]).to eq("ruby-version" => ".ruby-version")
    expect(smoke["steps"].map { |step| step["run"] }).to include("script/smoke_packaged_gem")
  end

  it "only tests Ruby versions the gemspec allows" do
    spec = Dir.chdir(DummyAppHelper::GEM_ROOT) { Gem::Specification.load("rails_agent_harness.gemspec") }

    test_job["strategy"]["matrix"]["ruby"].each do |ruby|
      expect(spec.required_ruby_version).to be_satisfied_by(Gem::Version.new(ruby))
    end
  end
end
