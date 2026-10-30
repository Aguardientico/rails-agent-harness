# frozen_string_literal: true

require "yaml"
require "generators/agent_harness/install/install_generator"

RSpec.describe AgentHarness::Generators::InstallGenerator, "rails-review skill" do
  let(:sections) { ["N+1 queries", "Missing indexes", "Strong parameters", "Callbacks", "Transactions", "Security", "Tests"] }

  around do |example|
    Dir.mktmpdir("agent_harness_install") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def run_generator(args = [])
    output = StringIO.new
    original = [$stdout, $stderr]
    $stdout = output
    $stderr = StringIO.new
    described_class.start(args, destination_root: root)
    output.string
  ensure
    $stdout, $stderr = original
  end

  def write(relative, contents = "")
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def skill_path = File.join(root, ".claude/skills/rails-review/SKILL.md")

  def skill = File.read(skill_path)

  def agents = File.read(File.join(root, "AGENTS.md"))

  def frontmatter
    YAML.safe_load(skill[/\A---\n(.*?)\n---\n/m, 1])
  end

  # The checklist: from the "Checklist" heading to the next heading of the same level.
  def checklist(text)
    text[/^(##+) Checklist\n\n(.*?)\n\n\1 /m, 2]
  end

  it "writes .claude/skills/rails-review/SKILL.md with valid frontmatter" do
    run_generator

    expect(frontmatter.keys).to eq(%w[name description])
    expect(frontmatter["name"]).to eq("rails-review")
    expect(frontmatter["description"]).to start_with("Review Rails code changes for N+1 queries")
    expect(frontmatter["description"].length).to be_between(1, 1023)
  end

  it "has the scope, checklist, verification and output sections, under 200 lines" do
    run_generator

    expect(skill).to include("## Scope", "## Checklist", "## Verify", "## Output format")
    expect(skill).to include("When reviewing on request, report findings only and don't edit files unless asked.",
      "When reviewing your own change before finishing it, fix the `blocker` and `should-fix` findings, then run `bin/agent-check` again.")
    expect(skill).to include("If there is no local `main` branch, use `origin/main`")
    expect(skill).to include("git diff --merge-base main", "git ls-files --others --exclude-standard", "`config/routes.rb`")
    expect(skill).to include("`blocker`, `should-fix`, `nit`", "`path:line - problem - concrete fix`", "No issues found", "bin/agent-check")
    expect(skill.lines.size).to be < 200
  end

  it "adds a Rails code review section to AGENTS.md after the agent-check section" do
    run_generator

    expect(agents).to include("## Rails code review", "When asked to review code (or before finishing a non-trivial change), follow this checklist",
      "When reviewing your own change before finishing it, fix the `blocker` and `should-fix` findings")
    expect(agents.index("## Verify your work")).to be < agents.index("## Rails code review")
    expect(agents).not_to include("name: rails-review")
  end

  it "renders the same checklist in SKILL.md and AGENTS.md, with every required section" do
    run_generator

    expect(checklist(skill)).not_to be_nil
    expect(checklist(skill)).to eq(checklist(agents))
    sections.each { |section| expect(checklist(skill)).to include("**#{section}**") }
  end

  it "recommends params.expect and concrete fixes" do
    run_generator

    expect(checklist(skill)).to include("params.expect(post: [:title, :body])", "permit!", "find_each", "after_commit",
      "save!", "with_lock", "current_user.posts.find(params[:id])", "unique: true", "url_from(params[:url])")
    expect(checklist(skill)).to include("`<%==`")
  end

  it "adapts to the schema format" do
    run_generator
    expect(checklist(skill)).to include("`db/schema.rb`")

    write("db/structure.sql")
    run_generator(["--force"])
    expect(checklist(skill)).to include("`db/structure.sql`")
    expect(checklist(skill)).not_to include("db/schema.rb")
  end

  it "adapts to Brakeman and the test framework" do
    write("spec/rails_helper.rb")
    run_generator
    expect(checklist(skill)).to include("spec under `spec/`", "request specs")
    expect(checklist(skill)).not_to include("brakeman")

    FileUtils.rm_rf(File.join(root, "spec"))
    FileUtils.mkdir_p(File.join(root, "test"))
    write("bin/brakeman")
    run_generator(["--force"])
    expect(checklist(skill)).to include("test under `test/`", "Run `bin/brakeman`")
  end

  it "uses the configured base branch in the scope" do
    write("config/agent_harness.yml", "base_branch: develop\n")

    run_generator

    expect(skill).to include("git diff --merge-base develop")
  end

  it "is idempotent" do
    run_generator
    first = skill

    output = run_generator

    expect(skill).to eq(first)
    expect(output).to include("identical  .claude/skills/rails-review/SKILL.md")
  end

  it "keeps a changed SKILL.md unless --force, without prompting" do
    write(".claude/skills/rails-review/SKILL.md", "my edits\n")

    output = run_generator

    expect(skill).to eq("my edits\n")
    expect(output).to include("exists  .claude/skills/rails-review/SKILL.md (differs; kept, use --force to overwrite)")

    run_generator(["--force"])
    expect(skill).to start_with("---\nname: rails-review\n")
  end

  it "skips the skill with --skip-skills but keeps the AGENTS.md section" do
    output = run_generator(["--skip-skills"])
    expect(output).not_to include("SKILL.md")

    expect(File).not_to exist(skill_path)
    expect(agents).to include("## Rails code review")
  end
end
