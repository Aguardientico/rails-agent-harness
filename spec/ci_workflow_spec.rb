# frozen_string_literal: true

require "yaml"

RSpec.describe ".github/workflows/ci.yml" do
  subject(:workflow) { YAML.load_file(File.join(DummyAppHelper::GEM_ROOT, ".github/workflows/ci.yml")) }

  # YAML 1.1 parses the bare `on:` key as `true`.
  let(:triggers) { workflow.fetch(true) { workflow.fetch("on") } }
  let(:test_job) { workflow["jobs"]["test"] }

  # Expands a GitHub Actions matrix (cartesian product + `include`) into jobs.
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

  it "lints with standardrb on the latest Ruby" do
    lint = workflow["jobs"]["lint"]
    setup = lint["steps"].find { |step| step["uses"] == "ruby/setup-ruby@v1" }

    expect(setup["with"]).to include("ruby-version" => "4.0", "bundler-cache" => true)
    expect(lint["steps"].map { |step| step["run"] }).to include("bundle exec standardrb")
  end

  it "tests Ruby 3.3/3.4/4.0 on Rails 8.1 plus an allowed-to-fail Rails main job" do
    jobs = expand_matrix(test_job["strategy"]["matrix"])

    expect(test_job["strategy"]["fail-fast"]).to be(false)
    expect(jobs).to contain_exactly(
      {"ruby" => "3.3", "rails" => "8.1", "experimental" => false},
      {"ruby" => "3.4", "rails" => "8.1", "experimental" => false},
      {"ruby" => "4.0", "rails" => "8.1", "experimental" => false},
      {"ruby" => "4.0", "rails" => "main", "experimental" => true}
    )
    expect(test_job["continue-on-error"]).to eq("${{ matrix.experimental }}")
    expect(test_job["env"]).to eq("RAILS_VERSION" => "${{ matrix.rails }}")
    expect(test_job["name"]).to start_with("Ruby ${{ matrix.ruby }} / Rails ${{ matrix.rails }}")
    expect(test_job["steps"].map { |step| step["run"] }).to include("bundle exec rspec")
  end

  it "only tests Ruby versions the gemspec allows" do
    spec = Dir.chdir(DummyAppHelper::GEM_ROOT) { Gem::Specification.load("rails_agent_harness.gemspec") }

    test_job["strategy"]["matrix"]["ruby"].each do |ruby|
      expect(spec.required_ruby_version).to be_satisfied_by(Gem::Version.new(ruby))
    end
  end
end
