# frozen_string_literal: true

require "rails_agent_harness/version"

module RailsAgentHarness
  class Error < StandardError; end

  class ConfigurationError < Error; end

  # Hook input and subprocess output are UTF-8 whatever the locale says (LC_ALL=C reads them
  # as US-ASCII).
  def self.utf8(bytes) = String.new(bytes, encoding: Encoding::UTF_8).scrub
end

require "rails_agent_harness/configuration"
require "rails_agent_harness/railtie" if defined?(Rails::Railtie)
