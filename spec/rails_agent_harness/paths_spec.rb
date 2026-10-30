# frozen_string_literal: true

require "rails_agent_harness/paths"

RSpec.describe RailsAgentHarness::Paths do
  it "makes paths root-relative and rejects paths outside the root" do
    Dir.mktmpdir do |root|
      expect(described_class.relative(File.join(root, "app/models/post.rb"), root)).to eq("app/models/post.rb")
      expect(described_class.relative("app/models/post.rb", root)).to eq("app/models/post.rb")
      expect(described_class.relative(File.join(root, "app\\models\\post.rb"), root)).to eq("app/models/post.rb")
      expect(described_class.relative("/etc/hosts", root)).to be_nil
      expect(described_class.relative(File.join(root, "../x.rb"), root)).to be_nil
      expect(described_class.relative(File.join(root, "..x.rb"), root)).to eq("..x.rb")
    end
  end
end
