# frozen_string_literal: true

require "rails/railtie"

module RailsAgentHarness
  # Hooks the gem into a host Rails app. Generators under lib/generators are
  # discovered by Rails automatically; later issues may add rake tasks here.
  class Railtie < Rails::Railtie
    railtie_name :agent_harness
  end
end
