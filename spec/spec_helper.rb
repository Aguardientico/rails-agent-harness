# frozen_string_literal: true

require "rails_agent_harness"

# Generated files contain UTF-8; read them as such whatever the machine's locale. The
# library itself doesn't rely on this (see the US-ASCII spec in install_generator_spec.rb).
Encoding.default_external = Encoding::UTF_8

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include DummyAppHelper
end
