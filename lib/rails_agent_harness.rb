# frozen_string_literal: true

require "rails_agent_harness/version"

module RailsAgentHarness
  class Error < StandardError; end

  class ConfigurationError < Error; end
end

require "rails_agent_harness/configuration"
require "rails_agent_harness/railtie" if defined?(Rails::Railtie)
