# frozen_string_literal: true

require "rubygems/package"

RSpec.describe "rails_agent_harness.gemspec" do
  subject(:spec) do
    Dir.chdir(DummyAppHelper::GEM_ROOT) { Gem::Specification.load("rails_agent_harness.gemspec") }
  end

  it "has railties as its only runtime dependency" do
    runtime = spec.runtime_dependencies

    expect(runtime.map(&:name)).to eq(["railties"])
    expect(runtime.first.requirement).to eq(Gem::Requirement.new(">= 8.1", "< 9"))
  end

  it "packages only lib, the license, README and CHANGELOG" do
    expect(spec.files).not_to be_empty
    expect(spec.files).to all(match(%r{\A(lib/|LICENSE\.txt\z|README\.md\z|CHANGELOG\.md\z)}))
    expect(spec.files).to include("lib/rails_agent_harness.rb", "LICENSE.txt", "README.md")
    expect(spec.files.grep(%r{\A(spec|demo)/})).to be_empty
  end

  it "declares the required metadata" do
    expect(spec.license).to eq("MIT")
    expect(spec.required_ruby_version).to eq(Gem::Requirement.new(">= 3.3"))
    expect(spec.metadata).to include(
      "source_code_uri" => "https://github.com/Aguardientico/rails-agent-harness",
      "changelog_uri" => "https://github.com/Aguardientico/rails-agent-harness/blob/main/CHANGELOG.md",
      "bug_tracker_uri" => "https://github.com/Aguardientico/rails-agent-harness/issues",
      "rubygems_mfa_required" => "true"
    )
  end

  it "passes rubygems validation" do
    expect { spec.validate(false) }.not_to raise_error
  end

  it "builds without warnings and packages only the allowed files" do
    Dir.mktmpdir("agent_harness_gem") do |dir|
      gem_path = File.join(dir, "rails_agent_harness.gem")
      output, status = Open3.capture2e(
        "gem", "build", "rails_agent_harness.gemspec", "--output", gem_path,
        chdir: DummyAppHelper::GEM_ROOT
      )

      expect(status).to be_success, output
      expect(output).not_to match(/WARNING/i)
      packaged = Gem::Package.new(gem_path).contents
      expect(packaged).to all(match(%r{\A(lib/|LICENSE\.txt\z|README\.md\z|CHANGELOG\.md\z)}))
      expect(packaged).to include("lib/rails_agent_harness.rb", "lib/rails_agent_harness/railtie.rb")
    end
  end
end
