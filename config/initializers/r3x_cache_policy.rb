# frozen_string_literal: true

Rails.application.config.after_initialize do
  R3x::Policy.validate_skip_cache!
end
