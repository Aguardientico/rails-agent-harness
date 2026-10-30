# frozen_string_literal: true

require "generators/agent_harness/install/install_generator"

RSpec.describe AgentHarness::Generators::InstallGenerator, "Database changes section" do
  around do |example|
    Dir.mktmpdir("agent_harness_install") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def agents(args = [])
    original = [$stdout, $stderr]
    $stdout = StringIO.new
    $stderr = StringIO.new
    described_class.start(args, destination_root: root)
    File.read(File.join(root, "AGENTS.md"))
  ensure
    $stdout, $stderr = original
  end

  it "renders between the agent-check (30) and review (50) sections" do
    text = agents

    expect(text.index("## Verify your work")).to be < text.index("## Database changes")
    expect(text.index("## Database changes")).to be < text.index("## Rails code review")
    expect(text).to include(
      "`bin/rails g migration AddPublishedToPosts published:boolean`", "Never create a migration file by hand",
      "Run `bin/rails db:migrate`", "Never edit `db/schema.rb` by hand", "reversible",
      "index for every new foreign key", "`bin/agent-check` enforces this", "a hook blocks writing a new migration file"
    )
    expect(text).not_to include("algorithm: :concurrently")
  end

  it "adapts to structure.sql, PostgreSQL and --skip-claude-hooks" do
    FileUtils.mkdir_p(File.join(root, "db"))
    File.write(File.join(root, "db/structure.sql"), "")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config/database.yml"), "development:\n  adapter: postgresql\n")

    text = agents(["--skip-claude-hooks"])
    section = text[/## Database changes\n.*?(?=^## )/m]

    expect(section).to include("Never edit `db/structure.sql` by hand", "algorithm: :concurrently", "disable_ddl_transaction!")
    expect(section).not_to include("a hook blocks")
  end
end
