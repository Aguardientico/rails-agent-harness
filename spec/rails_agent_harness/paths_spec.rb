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

  it "matches files that don't exist yet under a symlinked root" do
    Dir.mktmpdir do |dir|
      real = File.join(dir, "real")
      link = File.join(dir, "link")
      FileUtils.mkdir_p(File.join(real, "db"))
      File.symlink(real, link)

      expect(described_class.relative(File.join(link, "db/migrate/new.rb"), link)).to eq("db/migrate/new.rb")
      expect(described_class.relative(File.join(real, "db/migrate/new.rb"), link)).to eq("db/migrate/new.rb")
      expect(described_class.relative(File.join(link, "db/migrate/new.rb"), real)).to eq("db/migrate/new.rb")
    end
  end
end
