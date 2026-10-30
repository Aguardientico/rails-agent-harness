# frozen_string_literal: true

require "rails_agent_harness/app_detector"

RSpec.describe RailsAgentHarness::AppDetector do
  around do |example|
    Dir.mktmpdir("agent_harness_app") do |dir|
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

  # A minimal but valid Gemfile.lock listing the given gems (name => version).
  def lockfile(gems)
    specs = gems.map { |name, version| "    #{name} (#{version})" }.join("\n")
    deps = gems.keys.map { |name| "  #{name}" }.join("\n")
    <<~LOCK
      GEM
        remote: https://rubygems.org/
        specs:
      #{specs}

      PLATFORMS
        ruby

      DEPENDENCIES
      #{deps}

      BUNDLED WITH
         2.6.0
    LOCK
  end

  def profile
    described_class.new(root).detect
  end

  it "loads without Rails" do
    lib = File.expand_path("../../lib", __dir__)
    script = <<~RUBY
      require "rails_agent_harness/app_detector"
      RailsAgentHarness::AppDetector.new(Dir.pwd).detect
      puts defined?(Rails) ? "rails" : "no rails"
    RUBY
    output, status = Open3.capture2e("ruby", "-I", lib, "-e", script, chdir: root)

    expect(status).to be_success, output
    expect(output.strip).to eq("no rails")
  end

  it "returns an AppProfile value object" do
    expect(profile).to be_a(RailsAgentHarness::AppProfile)
    expect(profile).to be_frozen
  end

  describe "rails_version" do
    it "uses the railties version from the lockfile" do
      write("Gemfile.lock", lockfile("rails" => "8.1.3", "railties" => "8.1.4"))

      expect(profile.rails_version).to eq("8.1.4")
    end

    it "falls back to the rails gem" do
      write("Gemfile.lock", lockfile("rails" => "8.1.3"))

      expect(profile.rails_version).to eq("8.1.3")
    end

    it "is nil when the lockfile has neither" do
      write("Gemfile.lock", lockfile("rake" => "13.3.0"))

      expect(profile.rails_version).to be_nil
    end

    it "uses the loaded Rails version when there is no lockfile" do
      stub_const("Rails::VERSION::STRING", "8.1.9")

      expect(profile.rails_version).to eq("8.1.9")
    end

    it "is nil without a lockfile or loaded Rails" do
      hide_const("Rails") if defined?(Rails)

      expect(profile.rails_version).to be_nil
    end

    it "treats a malformed lockfile as no gems" do
      write("Gemfile.lock", "GEM\n  specs:\n    <<<<<<< HEAD\n")
      hide_const("Rails") if defined?(Rails)

      expect(profile.rails_version).to be_nil
      expect(profile.rubocop?).to be(false)
    end
  end

  describe "test_framework" do
    it "is :rspec when the lockfile has rspec-rails" do
      write("Gemfile.lock", lockfile("rspec-rails" => "8.0.2"))

      expect(profile.test_framework).to eq(:rspec)
    end

    it "is :rspec when spec/rails_helper.rb exists" do
      write("spec/rails_helper.rb")

      expect(profile.test_framework).to eq(:rspec)
    end

    it "is :minitest when test/ exists" do
      FileUtils.mkdir_p(File.join(root, "test"))

      expect(profile.test_framework).to eq(:minitest)
    end

    it "prefers RSpec when both exist" do
      FileUtils.mkdir_p(File.join(root, "test"))
      write("spec/rails_helper.rb")

      expect(profile.test_framework).to eq(:rspec)
    end

    it "is :none otherwise" do
      expect(profile.test_framework).to eq(:none)
    end
  end

  describe "database" do
    {
      "postgresql" => :postgresql, "postgis" => :postgresql,
      "mysql2" => :mysql, "trilogy" => :mysql,
      "sqlite3" => :sqlite, "oracle_enhanced" => :unknown
    }.each do |adapter, database|
      it "maps the #{adapter} adapter to #{database.inspect}" do
        write("config/database.yml", "development:\n  adapter: #{adapter}\n")

        expect(profile.database).to eq(database)
      end
    end

    it "renders ERB and resolves aliases" do
      write("config/database.yml", <<~YAML)
        default: &default
          adapter: <%= "postgresql" %>
          max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
        development:
          <<: *default
          database: app_development
      YAML

      expect(profile.database).to eq(:postgresql)
    end

    it "reads the primary entry of a multi-database layout" do
      write("config/database.yml", <<~YAML)
        development:
          primary:
            adapter: trilogy
          cache:
            adapter: sqlite3
      YAML

      expect(profile.database).to eq(:mysql)
    end

    it "falls back to lockfile gems when database.yml is missing" do
      write("Gemfile.lock", lockfile("pg" => "1.6.2"))

      expect(profile.database).to eq(:postgresql)
    end

    it "falls back to lockfile gems when database.yml can't be read" do
      write("config/database.yml", "development:\n  adapter: <%= Rails.env %>\n")
      write("Gemfile.lock", lockfile("trilogy" => "2.9.0"))

      expect(profile.database).to eq(:mysql)
    end

    it "falls back to lockfile gems when there is no development adapter" do
      write("config/database.yml", "production:\n  adapter: postgresql\n")
      write("Gemfile.lock", lockfile("sqlite3" => "2.7.4"))

      expect(profile.database).to eq(:sqlite)
    end

    it "is :unknown with nothing to go on" do
      expect(profile.database).to eq(:unknown)
    end
  end

  describe "linters" do
    it "detects rubocop from the lockfile or .rubocop.yml" do
      expect(profile.rubocop?).to be(false)

      write(".rubocop.yml")
      expect(profile.rubocop?).to be(true)

      FileUtils.rm(File.join(root, ".rubocop.yml"))
      write("Gemfile.lock", lockfile("rubocop" => "1.81.0"))
      expect(profile.rubocop?).to be(true)
    end

    it "detects standard from the lockfile" do
      expect(profile.standard?).to be(false)

      write("Gemfile.lock", lockfile("standard" => "1.51.0", "rubocop" => "1.81.0"))
      expect(profile.standard?).to be(true)
    end

    it "detects brakeman from the lockfile or bin/brakeman" do
      expect(profile.brakeman?).to be(false)

      write("bin/brakeman")
      expect(profile.brakeman?).to be(true)

      FileUtils.rm(File.join(root, "bin/brakeman"))
      write("Gemfile.lock", lockfile("brakeman" => "7.1.0"))
      expect(profile.brakeman?).to be(true)
    end
  end

  describe "schema_format" do
    it "is :ruby by default" do
      expect(profile.schema_format).to eq(:ruby)
    end

    it "is :sql when db/structure.sql exists" do
      write("db/structure.sql")

      expect(profile.schema_format).to eq(:sql)
    end

    it "is :sql when config/application.rb sets it" do
      write("config/application.rb", "config.active_record.schema_format = :sql\n")

      expect(profile.schema_format).to eq(:sql)
    end

    it "is :sql when the development database sets it" do
      write("config/database.yml", "development:\n  adapter: postgresql\n  schema_format: sql\n")

      expect(profile.schema_format).to eq(:sql)
    end
  end
end
