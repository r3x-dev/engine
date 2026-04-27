# frozen_string_literal: true

require "ruby_llm"

RubyLLM.configure do |config|
  config.max_retries = 3
  config.retry_interval = 60.0
  config.retry_backoff_factor = 2
end
