Rails.application.config.after_initialize do
  if ENV["R3X_LLM_REFRESH_MODELS"] == "true"
    Rails.logger.info "[R3x::Llm] Refreshing LLM models from providers..."
    RubyLLM.models.refresh!
    Rails.logger.info "[R3x::Llm] LLM models refreshed successfully"
  end
end
