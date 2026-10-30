# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  # Fail loudly if the dummy app (or this gem) touches a deprecated Rails API.
  config.active_support.deprecation = :raise
end
