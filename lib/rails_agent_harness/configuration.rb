# frozen_string_literal: true

require "yaml"

module RailsAgentHarness
  # Loads config/agent_harness.yml from a host app and deep-merges it over
  # DEFAULTS. Deliberately free of any Rails dependency so bin/agent-check can
  # use it without booting the host app.
  class Configuration
    PATH = "config/agent_harness.yml"

    DEFAULTS = {
      "base_branch" => "main",
      "max_output_lines" => 40,
      "checks" => {
        "rubocop" => {"enabled" => true, "command" => nil},
        "brakeman" => {"enabled" => true, "command" => nil},
        "tests" => {"enabled" => true, "command" => nil}
      },
      "guards" => {
        "migrations" => {"enabled" => true},
        "schema" => {"enabled" => true}
      }
    }

    def self.deep_freeze(object)
      case object
      when Hash then object.each_value { |value| deep_freeze(value) }
      when Array then object.each { |value| deep_freeze(value) }
      end
      object.freeze
    end
    private_class_method :deep_freeze

    deep_freeze(DEFAULTS)

    def self.load(root = Dir.pwd)
      new(read(File.join(root.to_s, PATH)))
    end

    def self.read(path)
      return {} unless File.file?(path)

      data = YAML.safe_load_file(path, aliases: false)
      return {} if data.nil?
      unless data.is_a?(Hash)
        raise ConfigurationError, "#{path} must contain a YAML mapping at the top level, got #{data.class}"
      end

      validate_sections(data, path)
      warn_unknown_keys(data)
      data
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid YAML in #{path}: #{e.message}"
    end
    private_class_method :read

    # Empty sections (`checks:` with everything commented out) are treated as
    # absent; any other non-mapping value for a known section is an error.
    def self.validate_sections(data, path)
      %w[checks guards].each do |section|
        data.delete(section) if data.key?(section) && data[section].nil?
        next unless data.key?(section)

        unless data[section].is_a?(Hash)
          raise ConfigurationError, "#{path}: \"#{section}\" must be a mapping"
        end
        data[section].delete_if { |_name, entry| entry.nil? }
        data[section].each do |name, entry|
          next if entry.is_a?(Hash) || !DEFAULTS[section].key?(name.to_s)

          raise ConfigurationError, "#{path}: \"#{section}.#{name}\" must be a mapping"
        end
      end
    end
    private_class_method :validate_sections

    def self.warn_unknown_keys(data)
      unknown_keys(data, DEFAULTS).each do |key|
        warn %(agent_harness: unknown config key "#{key}" in #{PATH})
      end
      %w[checks guards].each do |section|
        next unless data[section].is_a?(Hash)

        unknown_keys(data[section], DEFAULTS[section], prefix: "#{section}.").each do |key|
          warn %(agent_harness: unknown config key "#{key}" in #{PATH})
        end
      end
    end
    private_class_method :warn_unknown_keys

    def self.unknown_keys(hash, known, prefix: "")
      hash.keys.map(&:to_s).reject { |key| known.key?(key) }.map { |key| "#{prefix}#{key}" }
    end
    private_class_method :unknown_keys

    def initialize(overrides = {})
      @data = deep_merge(DEFAULTS, overrides)
    end

    def base_branch
      @data["base_branch"]
    end

    def max_output_lines
      @data["max_output_lines"]
    end

    def check_enabled?(name)
      section_entry("checks", name)["enabled"] ? true : false
    end

    def check_command(name)
      section_entry("checks", name)["command"]
    end

    def guard_enabled?(name)
      section_entry("guards", name)["enabled"] ? true : false
    end

    def to_h
      deep_dup(@data)
    end

    private

    def section_entry(section, name)
      key = name.to_s
      unless DEFAULTS[section].key?(key)
        raise ArgumentError,
          "unknown #{section.chomp("s")} #{name.inspect} (known: #{DEFAULTS[section].keys.join(", ")})"
      end

      @data[section][key]
    end

    def deep_merge(base, overrides)
      result = deep_dup(base)
      overrides.each do |key, value|
        key = key.to_s
        result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge(result[key], value)
        else
          deep_dup(value)
        end
      end
      result
    end

    def deep_dup(object)
      case object
      when Hash then object.to_h { |key, value| [key.to_s, deep_dup(value)] }
      when Array then object.map { |value| deep_dup(value) }
      else object
      end
    end
  end
end
