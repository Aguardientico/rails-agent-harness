# frozen_string_literal: true

require "yaml"

RSpec.describe ".github/workflows/ci.yml" do
  subject(:workflow) { YAML.load_file(File.join(DummyAppHelper::GEM_ROOT, ".github/workflows/ci.yml")) }

  # YAML 1.1 parses the bare `on:` key as `true`.
  let(:triggers) { workflow.fetch(true) { workflow.fetch("on") } }

  it "runs on pushes to main and on pull requests" do
    expect(triggers["push"]).to eq("branches" => ["main"])
    expect(triggers).to have_key("pull_request")
  end

  it "lints with standardrb on Ruby 3.3" do
    lint = workflow["jobs"]["lint"]
    setup = lint["steps"].find { |step| step["uses"] == "ruby/setup-ruby@v1" }

    expect(setup["with"]).to include("ruby-version" => "3.3", "bundler-cache" => true)
    expect(lint["steps"].map { |step| step["run"] }).to include("bundle exec standardrb")
  end

  it "tests a 6-job Ruby x Rails matrix" do
    test = workflow["jobs"]["test"]
    matrix = test["strategy"]["matrix"]

    expect(test["strategy"]["fail-fast"]).to be(false)
    expect(matrix["ruby"]).to eq(%w[3.2 3.3])
    expect(matrix["rails"]).to eq(%w[7.1 7.2 8.0])
    expect(matrix["ruby"].product(matrix["rails"]).size).to eq(6)
    expect(test["env"]).to eq("RAILS_VERSION" => "${{ matrix.rails }}")
    expect(test["name"]).to eq("Ruby ${{ matrix.ruby }} / Rails ${{ matrix.rails }}")
    expect(test["steps"].map { |step| step["run"] }).to include("bundle exec rspec")
  end
end
