# frozen_string_literal: true

# Centralized wrapper for the Claude API.
# Handles model selection, message building, JSON parsing, and error fallback.
#
# Usage:
#   ClaudeService.call(
#     model: :haiku,
#     system_prompt: "You are a helpful assistant...",
#     user_message: "Terminé un trabajo con los Martínez",
#     context: { "stage" => "active", "history" => [...] }
#   )
#
# Returns a Hash with keys: message, action, action_data, new_stage,
# updated_context, should_save_message, intent.
# Keys are always in English; values in Spanish.
class ClaudeService
  MODELS = {
    haiku: "claude-haiku-4-5-20251001",
    sonnet: "claude-sonnet-4-6"
  }.freeze

  RESPONSE_KEYS = %w[
    message action action_data new_stage
    updated_context should_save_message intent
  ].freeze

  SAFE_FALLBACK = {
    "message" => "Lo siento, tuve un problema. ¿Puedes repetir eso?",
    "action" => "none",
    "action_data" => {},
    "new_stage" => nil,
    "updated_context" => {},
    "should_save_message" => false,
    "intent" => nil
  }.freeze

  def self.call(model:, system_prompt:, user_message:, context: {})
    response = request_claude(model, system_prompt, user_message, context)
    parse_response(response)
  rescue Anthropic::Client::ApiError, Anthropic::Client::RateLimitError, Anthropic::Client::OverloadedError => e
    handle_api_error(model, system_prompt, user_message, context, e)
  rescue StandardError => e
    Rails.logger.error("[ClaudeService] Unexpected error: #{e.class} — #{e.message}")
    SAFE_FALLBACK.dup
  end

  # --- Private helpers ---

  def self.request_claude(model, system_prompt, user_message, context)
    messages = build_messages(user_message, context)

    Anthropic.messages.create(
      model: MODELS.fetch(model),
      max_tokens: 1024,
      system: system_prompt,
      messages: messages
    )
  end

  def self.build_messages(user_message, context)
    messages = []

    # Append prior conversation history from context if available
    history = context["history"] || context[:history]
    if history.is_a?(Array)
      history.each do |entry|
        role = entry["role"] || entry[:role]
        content = entry["content"] || entry[:content]
        messages << { role: role, content: content } if role && content
      end
    end

    messages << { role: "user", content: user_message }
    messages
  end

  def self.parse_response(api_response)
    raw_text = extract_text(api_response)
    parsed = JSON.parse(raw_text)

    unless parsed.is_a?(Hash)
      Rails.logger.warn("[ClaudeService] Response is not a JSON object: #{raw_text.truncate(500)}")
      return SAFE_FALLBACK.dup
    end

    normalize_response(parsed)
  rescue JSON::ParserError => e
    Rails.logger.error("[ClaudeService] JSON parse failure: #{e.message} — raw: #{raw_text&.truncate(500)}")
    SAFE_FALLBACK.dup
  end

  def self.extract_text(api_response)
    content = api_response.dig("content", 0, "text") ||
              api_response.dig(:content, 0, :text)

    return content if content

    # Some gem versions return the response differently
    api_response.to_s
  end

  def self.normalize_response(parsed)
    normalized = SAFE_FALLBACK.dup

    RESPONSE_KEYS.each do |key|
      normalized[key] = parsed[key] if parsed.key?(key)
    end

    normalized
  end

  def self.handle_api_error(model, system_prompt, user_message, context, error)
    Rails.logger.error("[ClaudeService] #{error.class} with model #{model}: #{error.message}")

    # Fall back to haiku if sonnet failed
    if model == :sonnet
      Rails.logger.info("[ClaudeService] Falling back from sonnet to haiku")
      return call(model: :haiku, system_prompt: system_prompt, user_message: user_message, context: context)
    end

    SAFE_FALLBACK.dup
  end

  private_class_method :request_claude, :build_messages, :parse_response,
                       :extract_text, :normalize_response, :handle_api_error
end
