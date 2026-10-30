# frozen_string_literal: true

module RailsAgentHarness
  # Outcome of one check. `status` is :pass, :fail or :skip; `details` are short lines.
  CheckResult = Data.define(:name, :status, :summary, :details) do
    def initialize(name:, status:, summary: nil, details: [])
      super
    end

    def pass? = status == :pass

    def fail? = status == :fail

    def skip? = status == :skip
  end

  module Checks
    @registry = []

    class << self
      # The checks bin/agent-check runs, in order. This is the only place that lists them.
      attr_reader :registry

      def register(klass, position: :last)
        raise ArgumentError, "position must be :first or :last" unless %i[first last].include?(position)

        @registry.delete(klass)
        (position == :first) ? @registry.unshift(klass) : @registry.push(klass)
        klass
      end

      def find(name)
        registry.find { |klass| klass.check_name == name.to_s }
      end
    end
  end
end

require "rails_agent_harness/checks/base"
require "rails_agent_harness/checks/rubocop"
require "rails_agent_harness/checks/brakeman"
require "rails_agent_harness/checks/tests"
require "rails_agent_harness/checks/migrations"

RailsAgentHarness::Checks.register(RailsAgentHarness::Checks::Rubocop)
RailsAgentHarness::Checks.register(RailsAgentHarness::Checks::Brakeman)
RailsAgentHarness::Checks.register(RailsAgentHarness::Checks::Tests)
RailsAgentHarness::Checks.register(RailsAgentHarness::Checks::Migrations, position: :first)
