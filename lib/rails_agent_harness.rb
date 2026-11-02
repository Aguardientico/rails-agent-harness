# frozen_string_literal: true

require "rails_agent_harness/version"

module RailsAgentHarness
  class Error < StandardError; end

  class ConfigurationError < Error; end

  def self.utf8(bytes) = String.new(bytes, encoding: Encoding::UTF_8).scrub
end

require "rails_agent_harness/configuration"
require "rails_agent_harness/railtie" if defined?(Rails::Railtie)
