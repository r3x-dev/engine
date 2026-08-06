# frozen_string_literal: true

return unless defined?(Flightdeck)

Flightdeck.configure do |config|
  if Rails.env.development? || Rails.env.test?
    config.skip_authentication = true
  else
    auth_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("FLIGHTDECK_AUTH_ENABLED", true))
    username = R3x::Env.fetch("FLIGHTDECK_USERNAME")
    password = R3x::Env.fetch("FLIGHTDECK_PASSWORD")

    if !auth_enabled
      config.skip_authentication = true
    elsif username.present? && password.present?
      config.http_basic = { username:, password: }
    end
  end
end
