# frozen_string_literal: true

require "rails_agent_harness/checks"

RSpec.describe RailsAgentHarness::Checks do
  around do |example|
    original = described_class.registry.dup
    example.run
  ensure
    described_class.registry.replace(original)
  end

  let(:dummy_check) do
    Class.new(RailsAgentHarness::Checks::Base) do
      check_name "dummy"

      def call = pass
    end
  end

  it "registers the default checks in order" do
    expect(described_class.registry.map(&:check_name)).to eq(%w[migrations rubocop brakeman tests])
  end

  it "registers a check at the end by default" do
    described_class.register(dummy_check)

    expect(described_class.registry.map(&:check_name)).to eq(%w[migrations rubocop brakeman tests dummy])
  end

  it "registers a check first with position: :first" do
    described_class.register(dummy_check, position: :first)

    expect(described_class.registry.map(&:check_name)).to eq(%w[dummy migrations rubocop brakeman tests])
  end

  it "doesn't register a check twice" do
    described_class.register(dummy_check)
    described_class.register(dummy_check, position: :first)

    expect(described_class.registry.map(&:check_name)).to eq(%w[dummy migrations rubocop brakeman tests])
  end

  it "rejects an unknown position" do
    expect { described_class.register(dummy_check, position: :middle) }.to raise_error(ArgumentError)
  end

  it "finds checks by name" do
    expect(described_class.find("tests")).to eq(RailsAgentHarness::Checks::Tests)
    expect(described_class.find(:nope)).to be_nil
  end

  it "keeps Module#name intact on check classes" do
    expect(RailsAgentHarness::Checks::Rubocop.name).to eq("RailsAgentHarness::Checks::Rubocop")
  end
end
