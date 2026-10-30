# frozen_string_literal: true

require "generators/agent_harness/install/install_generator"

RSpec.describe AgentHarness::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir("agent_harness_install") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def write(relative, contents = "")
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def read(relative)
    File.read(File.join(root, relative))
  end

  attr_reader :exit_status, :errors

  # Runs the generator quietly and returns what it printed on stdout. #exit_status is the
  # status it exited with (0 when it didn't call exit) and #errors what it printed on stderr.
  def run_generator(args = [])
    output = StringIO.new
    error_output = StringIO.new
    original = [$stdout, $stderr]
    $stdout = output
    $stderr = error_output
    @exit_status = 0
    begin
      described_class.start(args, destination_root: root)
    rescue SystemExit => e
      @exit_status = e.status
    end
    @errors = error_output.string
    output.string
  ensure
    $stdout, $stderr = original
  end

  def harness_block(relative)
    read(relative)[/<!-- BEGIN rails_agent_harness -->\n(.*)<!-- END rails_agent_harness -->/m, 1]
  end

  context "in a fresh app" do
    it "creates the config file, AGENTS.md and CLAUDE.md" do
      output = run_generator

      expect(output).to include("create  config/agent_harness.yml", "create  AGENTS.md", "create  CLAUDE.md")
      expect(read("AGENTS.md")).to start_with("<!-- BEGIN rails_agent_harness -->\n# Agent instructions")
      expect(read("AGENTS.md")).to end_with("<!-- END rails_agent_harness -->\n")
    end

    it "makes CLAUDE.md import AGENTS.md and nothing else" do
      run_generator

      expect(read("CLAUDE.md")).to eq(<<~MARKDOWN)
        <!-- BEGIN rails_agent_harness -->
        @AGENTS.md

        This project's agent instructions live in AGENTS.md (shared by Claude Code, Codex and Cursor). Read it before making changes.
        <!-- END rails_agent_harness -->
      MARKDOWN
    end

    it "prints the detected profile and next steps" do
      write("spec/rails_helper.rb")

      output = run_generator

      expect(output).to include("Test framework: rspec", "Database:       unknown", "Schema format:  ruby")
      expect(output).to include("Next steps:", "Commit AGENTS.md, CLAUDE.md, config/agent_harness.yml, bin/agent-check, .claude/settings.json, .claude/skills/rails-review/SKILL.md.")
    end
  end

  describe "config/agent_harness.yml" do
    def config
      RailsAgentHarness::Configuration.load(root)
    end

    it "documents every key of the default schema and loads without warnings" do
      run_generator

      expect { config }.not_to output.to_stderr
      expect(config.to_h.keys).to eq(RailsAgentHarness::Configuration::DEFAULTS.keys)
      yaml = read("config/agent_harness.yml")
      %w[base_branch max_output_lines checks rubocop brakeman tests command guards migrations schema].each do |key|
        expect(yaml).to match(/^\s*#.*\n\s*#{key}:/), "expected a comment above #{key}"
      end
    end

    it "disables checks for tools that weren't detected" do
      run_generator

      expect(config.check_enabled?(:rubocop)).to be(false)
      expect(config.check_enabled?(:brakeman)).to be(false)
      expect(config.check_enabled?(:tests)).to be(false)
      expect(config.guard_enabled?(:migrations)).to be(true)
    end

    it "enables checks for detected tools" do
      write(".rubocop.yml")
      write("bin/brakeman")
      FileUtils.mkdir_p(File.join(root, "test"))

      run_generator

      expect(config.check_enabled?(:rubocop)).to be(true)
      expect(config.check_enabled?(:brakeman)).to be(true)
      expect(config.check_enabled?(:tests)).to be(true)
    end

    it "is not overwritten when it already exists" do
      write("config/agent_harness.yml", "base_branch: develop\n")

      output = run_generator

      expect(read("config/agent_harness.yml")).to eq("base_branch: develop\n")
      expect(output).to include("exists  config/agent_harness.yml (skipped; use --force to overwrite)")
    end

    it "is overwritten with --force" do
      write("config/agent_harness.yml", "base_branch: develop\n")

      run_generator(["--force"])

      expect(config.base_branch).to eq("main")
    end
  end

  describe "AGENTS.md and CLAUDE.md" do
    it "appends the block to existing files without markers, keeping the user's content" do
      write("AGENTS.md", "# My team rules\n\nAlways be nice.\n")
      write("CLAUDE.md", "Use plan mode.\n")

      run_generator

      expect(read("AGENTS.md")).to start_with("# My team rules\n\nAlways be nice.\n\n<!-- BEGIN rails_agent_harness -->\n")
      expect(read("CLAUDE.md")).to start_with("Use plan mode.\n\n<!-- BEGIN rails_agent_harness -->\n@AGENTS.md\n")
    end

    it "replaces only the marked block in existing files with markers" do
      write("AGENTS.md", <<~MARKDOWN)
        Before.

        <!-- BEGIN rails_agent_harness -->
        stale content
        <!-- END rails_agent_harness -->

        After.
      MARKDOWN

      run_generator

      agents = read("AGENTS.md")
      expect(agents).to start_with("Before.\n\n<!-- BEGIN rails_agent_harness -->\n# Agent instructions")
      expect(agents).to end_with("<!-- END rails_agent_harness -->\n\nAfter.\n")
      expect(agents).not_to include("stale content")
      expect(agents.scan("<!-- BEGIN rails_agent_harness -->").size).to eq(1)
    end

    it "is idempotent" do
      write("AGENTS.md", "Mine.\n")
      run_generator
      first = %w[AGENTS.md CLAUDE.md config/agent_harness.yml].to_h { |file| [file, read(file)] }

      output = run_generator

      expect(%w[AGENTS.md CLAUDE.md config/agent_harness.yml].to_h { |file| [file, read(file)] }).to eq(first)
      expect(output).to include("identical  AGENTS.md", "identical  CLAUDE.md")
      expect(output).not_to include("conflict")
    end

    it "leaves a file with a BEGIN marker but no END marker untouched, writes the rest and exits non-zero" do
      write("AGENTS.md", "<!-- BEGIN rails_agent_harness -->\nhalf a block\n")

      output = run_generator

      expect(read("AGENTS.md")).to eq("<!-- BEGIN rails_agent_harness -->\nhalf a block\n")
      expect(output).to include("error  AGENTS.md has unmatched <!-- BEGIN rails_agent_harness -->")
      expect(output).not_to include("Next steps:")
      expect(read("CLAUDE.md")).to include("@AGENTS.md")
      expect(File).to exist(File.join(root, "config/agent_harness.yml"))
      expect(exit_status).to eq(1)
      expect(errors).to include("need fixing by hand", "AGENTS.md: unmatched <!-- BEGIN rails_agent_harness --> / <!-- END rails_agent_harness --> markers")
    end

    it "reports nested markers and a lone END marker" do
      nested = "<!-- BEGIN rails_agent_harness -->\n<!-- BEGIN rails_agent_harness -->\nx\n<!-- END rails_agent_harness -->\n<!-- END rails_agent_harness -->\n"
      write("AGENTS.md", nested)
      write("CLAUDE.md", "mine\n<!-- END rails_agent_harness -->\n")

      run_generator

      expect(read("AGENTS.md")).to eq(nested)
      expect(read("CLAUDE.md")).to eq("mine\n<!-- END rails_agent_harness -->\n")
      expect(exit_status).to eq(1)
      expect(errors).to include("AGENTS.md: unmatched", "CLAUDE.md: unmatched")
    end

    it "reports a stray BEGIN marker after a complete block" do
      stray = "<!-- BEGIN rails_agent_harness -->\nold\n<!-- END rails_agent_harness -->\n<!-- BEGIN rails_agent_harness -->\n"
      write("AGENTS.md", stray)

      run_generator

      expect(read("AGENTS.md")).to eq(stray)
      expect(exit_status).to eq(1)
    end

    it "works when the default external encoding isn't UTF-8" do
      write("AGENTS.md", "Équipe: règles → ici.\n")
      original = Encoding.default_external
      Encoding.default_external = Encoding::US_ASCII
      begin
        run_generator
      ensure
        Encoding.default_external = original
      end

      expect(exit_status).to eq(0)
      expect(read("AGENTS.md")).to start_with("Équipe: règles → ici.\n\n<!-- BEGIN rails_agent_harness -->")
    end

    it "exits zero when nothing needs fixing" do
      run_generator

      expect(exit_status).to eq(0)
      expect(errors).to be_empty
    end

    it "collapses several marked blocks into one" do
      write("AGENTS.md", <<~MARKDOWN)
        <!-- BEGIN rails_agent_harness -->
        old one
        <!-- END rails_agent_harness -->
        Mine.
        <!-- BEGIN rails_agent_harness -->
        old two
        <!-- END rails_agent_harness -->
      MARKDOWN

      run_generator

      agents = read("AGENTS.md")
      expect(agents.scan("<!-- BEGIN rails_agent_harness -->").size).to eq(1)
      expect(agents).to include("# Agent instructions", "Mine.")
      expect(agents).not_to include("old one", "old two")
    end

    it "keeps a changed block with --skip" do
      write("AGENTS.md", "<!-- BEGIN rails_agent_harness -->\nstale\n<!-- END rails_agent_harness -->\n")

      run_generator(["--skip"])

      expect(read("AGENTS.md")).to include("stale")
    end

    it "doesn't overwrite AGENTS.md with a self-import when CLAUDE.md links to it" do
      write("AGENTS.md", "Shared.\n")
      File.symlink("AGENTS.md", File.join(root, "CLAUDE.md"))

      output = run_generator

      expect(File.symlink?(File.join(root, "CLAUDE.md"))).to be(true)
      expect(read("AGENTS.md")).to include("Shared.", "# Agent instructions")
      expect(read("AGENTS.md")).not_to include("@AGENTS.md")
      expect(output).to include("skip  CLAUDE.md (same file as AGENTS.md")
    end
  end

  describe "AGENTS.md content" do
    let(:partials) { Dir[File.join(described_class.source_root, "agents_md", "*.md.tt")].map { |path| File.basename(path) } }

    it "renders the partials in filename order" do
      run_generator
      block = harness_block("AGENTS.md")

      expect(partials).to include("00_header.md.tt", "10_commands.md.tt", "20_conventions.md.tt")
      positions = ["# Agent instructions", "## Commands", "## Rails conventions"].map { |heading| block.index(heading) }
      expect(positions).to eq(positions.sort)
      expect(positions).to all(be_a(Integer))
    end

    it "renders an added partial according to its filename" do
      templates = Dir.mktmpdir("agent_harness_templates")
      FileUtils.cp_r("#{described_class.source_root}/.", templates)
      File.write(File.join(templates, "agents_md", "15_spec_extra.md.tt"), "## Extra <%= profile.test_framework %>\n")
      allow(described_class).to receive(:source_root).and_return(templates)

      run_generator
      block = harness_block("AGENTS.md")
      FileUtils.rm_rf(templates)

      expect(block.index("## Commands")).to be < block.index("## Extra none")
      expect(block.index("## Extra none")).to be < block.index("## Rails conventions")
    end

    it "does not render the partials README" do
      run_generator

      expect(read("AGENTS.md")).not_to include("AGENTS.md partials")
    end

    it "lists the detected stack" do
      write("Gemfile.lock", <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            railties (8.1.4)
            pg (1.6.2)
            standard (1.51.0)
            rubocop (1.81.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          railties

        BUNDLED WITH
           2.6.0
      LOCK
      write("db/structure.sql")

      run_generator

      expect(read("AGENTS.md")).to include(
        "- Rails: 8.1.4", "- Tests: none detected", "- Database: PostgreSQL",
        "- Linter: Standard", "- Security scanner: none detected", "- Schema format: SQL (`db/structure.sql`)",
        "Never edit `db/structure.sql` by hand", "PostgreSQL: prefer `jsonb`"
      )
    end

    it "renders RSpec commands" do
      write("spec/rails_helper.rb")

      run_generator

      expect(read("AGENTS.md")).to include(
        "- Run all tests: `bundle exec rspec`",
        "- Run one test: `bundle exec rspec path/to/file_spec.rb:LINE`",
        "Add or update a spec under `spec/`"
      )
    end

    it "renders Minitest commands" do
      FileUtils.mkdir_p(File.join(root, "test"))

      run_generator

      expect(read("AGENTS.md")).to include(
        "- Run all tests: `bin/rails test`",
        "- Run one test: `bin/rails test path/to/file_test.rb:LINE`",
        "Add or update a test under `test/`"
      )
    end

    it "omits test commands when no test framework is detected" do
      run_generator

      expect(read("AGENTS.md")).not_to include("Run all tests")
    end

    it "omits the lint and security commands when no tool is detected" do
      run_generator

      expect(read("AGENTS.md")).not_to include("- Lint:", "- Security scan:")
    end

    it "prefers app binstubs for setup, lint, security and CI" do
      %w[bin/setup bin/rubocop bin/brakeman bin/ci].each { |file| write(file) }

      run_generator

      expect(read("AGENTS.md")).to include(
        "- Setup: `bin/setup`", "- Lint: `bin/rubocop`", "- Security scan: `bin/brakeman`", "`bin/ci`"
      )
    end

    it "falls back to bundle exec commands" do
      write(".rubocop.yml")
      write("Gemfile.lock", <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            brakeman (7.1.0)
            rubocop (1.81.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          brakeman

        BUNDLED WITH
           2.6.0
      LOCK

      run_generator

      expect(read("AGENTS.md")).to include(
        "- Setup: `bundle install && bin/rails db:prepare`",
        "- Lint: `bundle exec rubocop`",
        "- Security scan: `bundle exec brakeman`"
      )
      expect(read("AGENTS.md")).not_to include("bin/ci")
    end

    it "uses standardrb for Standard apps without a .rubocop.yml" do
      write("Gemfile.lock", <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            rubocop (1.81.0)
            standard (1.51.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          standard

        BUNDLED WITH
           2.6.0
      LOCK

      run_generator

      expect(read("AGENTS.md")).to include("- Lint: `bundle exec standardrb`")
    end

    it "keeps the conventions section short" do
      run_generator
      conventions = harness_block("AGENTS.md")[/^## Rails conventions\n.*?(?=^## |\z)/m]

      expect(conventions.lines.size).to be < 60
    end
  end
end
