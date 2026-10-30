# frozen_string_literal: true

require "bundler"
require "erb"
require "yaml"

module RailsAgentHarness
  # What AppDetector found out about a host app.
  AppProfile = Data.define(
    :rails_version, :test_framework, :database, :rubocop, :standard, :brakeman, :schema_format
  ) do
    def rubocop? = rubocop

    def standard? = standard

    def brakeman? = brakeman
  end

  # Detects a host app's stack from files on disk, without booting Rails.
  #
  # Rules (deliberately simple):
  # - Gems come from <root>/Gemfile.lock (Bundler::LockfileParser); no lockfile means no gems.
  # - rails_version: lockfile version of railties (fallback: rails); without a lockfile,
  #   Rails::VERSION::STRING when Rails is loaded; else nil.
  # - test_framework: :rspec if the lockfile has rspec-rails or spec/rails_helper.rb exists;
  #   else :minitest if test/ exists; else :none. RSpec wins when both exist.
  # - database: the development adapter in config/database.yml (ERB, then YAML; flat or
  #   multi-database with a `primary:` entry). postgresql/postgis => :postgresql,
  #   mysql2/trilogy => :mysql, sqlite3 => :sqlite, any other adapter => :unknown. If the file
  #   is missing, unreadable or has no development adapter, fall back to lockfile gems
  #   (pg, mysql2/trilogy, sqlite3); else :unknown.
  # - rubocop?: lockfile has rubocop or .rubocop.yml exists. standard?: lockfile has standard.
  #   brakeman?: lockfile has brakeman or bin/brakeman exists.
  # - schema_format: :sql if db/structure.sql exists, config/application.rb sets
  #   `schema_format = :sql`, or the development database entry sets `schema_format: sql`;
  #   else :ruby.
  class AppDetector
    ADAPTERS = {
      "postgresql" => :postgresql, "postgis" => :postgresql,
      "mysql2" => :mysql, "trilogy" => :mysql,
      "sqlite3" => :sqlite
    }.freeze
    DATABASE_GEMS = {"pg" => :postgresql, "mysql2" => :mysql, "trilogy" => :mysql, "sqlite3" => :sqlite}.freeze

    def initialize(root)
      @root = root.to_s
    end

    def detect
      AppProfile.new(
        rails_version: rails_version,
        test_framework: test_framework,
        database: database,
        rubocop: gem?("rubocop") || file?(".rubocop.yml"),
        standard: gem?("standard"),
        brakeman: gem?("brakeman") || file?("bin/brakeman"),
        schema_format: schema_format
      )
    end

    private

    def rails_version
      version = gems["railties"] || gems["rails"]
      return version if version
      return Rails::VERSION::STRING if !file?("Gemfile.lock") && defined?(Rails::VERSION)

      nil
    end

    def test_framework
      if gem?("rspec-rails") || file?("spec/rails_helper.rb")
        :rspec
      elsif File.directory?(path("test"))
        :minitest
      else
        :none
      end
    end

    def database
      adapter = development_database_config&.fetch("adapter", nil)
      return ADAPTERS.fetch(adapter.to_s, :unknown) if adapter

      DATABASE_GEMS.find { |name, _database| gem?(name) }&.last || :unknown
    end

    def schema_format
      return :sql if file?("db/structure.sql")
      return :sql if file?("config/application.rb") && File.read(path("config/application.rb")).match?(/schema_format\s*=\s*:sql/)
      return :sql if development_database_config&.fetch("schema_format", nil).to_s == "sql"

      :ruby
    end

    # The development entry of config/database.yml (the `primary:` one in a multi-database
    # layout), or nil when the file is missing or can't be read.
    def development_database_config
      return @development_database_config if defined?(@development_database_config)

      @development_database_config = begin
        yaml = ERB.new(File.read(path("config/database.yml"))).result
        development = YAML.safe_load(yaml, aliases: true)&.fetch("development", nil)
        development = development["primary"] if development.is_a?(Hash) && development["primary"].is_a?(Hash)
        development.is_a?(Hash) ? development : nil
      rescue StandardError, SyntaxError
        nil
      end
    end

    # Gem name => version string, from the lockfile.
    def gems
      @gems ||= begin
        lockfile = File.read(path("Gemfile.lock"))
        Bundler::LockfileParser.new(lockfile).specs.to_h { |spec| [spec.name, spec.version.to_s] }
      rescue SystemCallError, Bundler::LockfileError
        {}
      end
    end

    def gem?(name)
      gems.key?(name)
    end

    def file?(relative)
      File.file?(path(relative))
    end

    def path(relative)
      File.join(@root, relative)
    end
  end
end
