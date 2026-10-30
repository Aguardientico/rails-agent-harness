# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = true
  config.consider_all_requests_local = true
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
end
