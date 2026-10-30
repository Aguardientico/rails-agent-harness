# frozen_string_literal: true

RSpec.describe RailsAgentHarness do
  it "has a valid version" do
    expect(Gem::Version.correct?(RailsAgentHarness::VERSION)).to be(true)
    expect(RailsAgentHarness::VERSION).to eq("0.1.0")
  end

  it "defines the error hierarchy" do
    expect(RailsAgentHarness::Error.superclass).to eq(StandardError)
    expect(RailsAgentHarness::ConfigurationError.superclass).to eq(RailsAgentHarness::Error)
  end

  it "loads without Rails and skips the Railtie" do
    lib = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      require "rails_agent_harness"
      p RailsAgentHarness::Configuration.load(".").to_h
      puts defined?(Rails) ? "rails" : "no rails"
      puts defined?(RailsAgentHarness::Railtie) ? "railtie" : "no railtie"
    RUBY
    output, status = Open3.capture2e("ruby", "-I", lib, "-e", script, chdir: Dir.tmpdir)

    expect(status).to be_success, output
    expect(output).to include(%("base_branch" => "main")).or include(%("base_branch"=>"main"))
    expect(output).to include("no rails", "no railtie")
  end
end
