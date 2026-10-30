# frozen_string_literal: true

require "yaml"

module RailsAgentHarness
  # Loads config/agent_harness.yml from a host app and deep-merges it over
  # DEFAULTS. Deliberately free of any Rails dependency so bin/agent-check can
  # use it without booting the host app.
  class Configuration
    PATH = "config/agent_harness.yml"
    SECTIONS = %w[checks guards].freeze

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

    module DeepFreeze
      def self.call(object)
        case object
        when Hash then object.each_value { |value| call(value) }
        when Array then object.each { |value| call(value) }
        end
        object.freeze
      end
    end
    private_constant :DeepFreeze

    DeepFreeze.call(DEFAULTS)

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
      drop_unknown_keys(data)
      validate_values(data, path)
      data
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid YAML in #{path}: #{e.message}"
    end
    private_class_method :read

    # Empty known sections and entries (`checks:` with everything commented
    # out) are treated as absent; any other non-mapping value for them is an
    # error. Unknown entries are left alone so they still get a warning.
    def self.validate_sections(data, path)
      SECTIONS.each do |section|
        data.delete(section) if data.key?(section) && data[section].nil?
        next unless data.key?(section)

        unless data[section].is_a?(Hash)
          raise ConfigurationError, "#{path}: \"#{section}\" must be a mapping"
        end
        data[section].delete_if { |name, entry| entry.nil? && DEFAULTS[section].key?(name) }
        data[section].each do |name, entry|
          next if entry.is_a?(Hash) || !DEFAULTS[section].key?(name)

          raise ConfigurationError, "#{path}: \"#{section}.#{name}\" must be a mapping"
        end
      end
    end
    private_class_method :validate_sections

    # Warns once per unknown key, then removes it so callers (and #to_h) only
    # ever see the documented schema.
    def self.drop_unknown_keys(data)
      keys = drop_unknown(data, DEFAULTS)
      SECTIONS.each do |section|
        next unless data.key?(section)

        keys += drop_unknown(data[section], DEFAULTS[section], prefix: "#{section}.")
        data[section].each do |name, entry|
          keys += drop_unknown(entry, DEFAULTS[section][name], prefix: "#{section}.#{name}.")
        end
      end
      keys.each { |key| warn %(agent_harness: unknown config key "#{key}" in #{PATH}) }
    end
    private_class_method :drop_unknown_keys

    def self.drop_unknown(hash, known, prefix: "")
      unknown = hash.keys.reject { |key| known.key?(key) }
      unknown.each { |key| hash.delete(key) }
      unknown.map { |key| "#{prefix}#{key}" }
    end
    private_class_method :drop_unknown

    # Expected type of every known scalar setting, as [description, test].
    VALUE_TYPES = {
      "base_branch" => ["a non-empty string", ->(value) { value.is_a?(String) && !value.empty? }],
      "max_output_lines" => ["a positive integer", ->(value) { value.is_a?(Integer) && value.positive? }],
      "enabled" => ["true or false", ->(value) { value == true || value == false }],
      "command" => ["a string or null", ->(value) { value.nil? || value.is_a?(String) }]
    }.freeze
    private_constant :VALUE_TYPES

    # Type-checks every scalar the file sets (unknown keys are already gone).
    def self.validate_values(data, path)
      check_types(data, path)
      SECTIONS.each do |section|
        data.fetch(section, {}).each do |name, entry|
          check_types(entry, path, prefix: "#{section}.#{name}.")
        end
      end
    end
    private_class_method :validate_values

    def self.check_types(hash, path, prefix: "")
      hash.each do |key, value|
        next unless VALUE_TYPES.key?(key)

        expected, valid = VALUE_TYPES[key]
        next if valid.call(value)

        raise ConfigurationError, "#{path}: \"#{prefix}#{key}\" must be #{expected}, got #{value.inspect}"
      end
    end
    private_class_method :check_types

    private_class_method :new

    def initialize(overrides = {})
      @data = DeepFreeze.call(deep_merge(DEFAULTS, overrides))
    end

    def base_branch
      @data["base_branch"]
    end

    def max_output_lines
      @data["max_output_lines"]
    end

    def check_enabled?(name)
      section_entry("checks", name)["enabled"]
    end

    def check_command(name)
      section_entry("checks", name)["command"]
    end

    def guard_enabled?(name)
      section_entry("guards", name)["enabled"]
    end

    # A mutable deep copy; changing it never affects this configuration.
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
      when String then object.dup
      else object
      end
    end
  end
end
