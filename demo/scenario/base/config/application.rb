# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"

require "rails_agent_harness"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
  end
end
