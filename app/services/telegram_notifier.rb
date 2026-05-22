# frozen_string_literal: true

require "net/http"
require "json"

# Sends notifications to admin via Telegram bot.
# Used to alert when clients request services in unavailable areas.
class TelegramNotifier
  BASE_URL = "https://api.telegram.org"

  # Sends notification when a client requests service in an unavailable area.
  # Failures are logged but do not block the main flow.
  #
  # @param client [Client] The client record requesting service
  # @param category [String] The service category requested
  # @param city [String] The city where service was requested
  # @return [Net::HTTPResponse, nil] Returns response on success, nil on failure (never raises)
  def self.notify_unavailable_area(client:, category:, city:)
    message = build_message(client, category, city)
    send_telegram_message(message)
  end

  private

  # Builds the notification message with client details and timestamp.
  def self.build_message(client, category, city)
    "🔔 Nueva solicitud sin técnico\n" \
    "👤 #{client.name}\n" \
    "📱 #{client.phone}\n" \
    "🔧 #{category}\n" \
    "📍 #{city}\n" \
    "⏰ #{Time.current.strftime('%d/%m/%Y %H:%M')}"
  end

  # Sends message to Telegram via Bot API using Net::HTTP.
  # Logs errors but does not raise exceptions to avoid blocking main flow.
  def self.send_telegram_message(text)
    unless telegram_configured?
      Rails.logger.warn(
        "[TelegramNotifier] Telegram not configured. " \
        "Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID. " \
        "Notification skipped."
      )
      return nil
    end

    uri = URI("#{BASE_URL}/bot#{ENV['TELEGRAM_BOT_TOKEN']}/sendMessage")

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = {
      chat_id: ENV['TELEGRAM_CHAT_ID'],
      text: text
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end

    handle_response(response, text)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error(
      "[TelegramNotifier] Timeout sending notification: #{e.class} — #{e.message}"
    )
    nil
  rescue SocketError => e
    Rails.logger.error(
      "[TelegramNotifier] Network error sending notification: #{e.message}. " \
      "Check internet connectivity."
    )
    nil
  rescue URI::InvalidURIError => e
    Rails.logger.error(
      "[TelegramNotifier] Invalid Telegram Bot Token format: #{e.message}"
    )
    nil
  rescue JSON::GeneratorError => e
    Rails.logger.error(
      "[TelegramNotifier] Failed to encode message as JSON: #{e.message}. " \
      "Message text: #{text.inspect}"
    )
    nil
  rescue StandardError => e
    Rails.logger.error(
      "[TelegramNotifier] Unexpected error sending notification: " \
      "#{e.class} — #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    )
    nil
  end

  # Handles HTTP response from Telegram API and logs appropriate messages.
  def self.handle_response(response, text)
    if response.is_a?(Net::HTTPSuccess)
      Rails.logger.info("[TelegramNotifier] Notification sent successfully")
      response
    else
      log_api_error(response, text)
      nil
    end
  end

  # Logs detailed error information based on HTTP status code.
  def self.log_api_error(response, text)
    error_body = parse_error_body(response.body)
    error_description = error_body.dig("description") || "No description provided"

    case response.code.to_i
    when 400
      Rails.logger.error(
        "[TelegramNotifier] Bad Request (400): #{error_description}. " \
        "Check chat_id format or message content. Message: #{text.inspect}"
      )
    when 401
      Rails.logger.error(
        "[TelegramNotifier] Unauthorized (401): #{error_description}. " \
        "Invalid TELEGRAM_BOT_TOKEN. Please verify token configuration."
      )
    when 403
      Rails.logger.error(
        "[TelegramNotifier] Forbidden (403): #{error_description}. " \
        "Bot may be blocked by user or lacks permissions for chat_id: #{ENV['TELEGRAM_CHAT_ID']}"
      )
    when 404
      Rails.logger.error(
        "[TelegramNotifier] Not Found (404): #{error_description}. " \
        "Invalid bot token or API endpoint."
      )
    when 429
      retry_after = error_body.dig("parameters", "retry_after") || "unknown"
      Rails.logger.error(
        "[TelegramNotifier] Rate Limited (429): #{error_description}. " \
        "Retry after #{retry_after} seconds."
      )
    when 500..599
      Rails.logger.error(
        "[TelegramNotifier] Telegram Server Error (#{response.code}): #{error_description}. " \
        "Telegram API may be experiencing issues. Will retry on next notification."
      )
    else
      Rails.logger.error(
        "[TelegramNotifier] Unexpected HTTP #{response.code}: #{error_description}. " \
        "Response body: #{response.body}"
      )
    end
  end

  # Safely parses error response body as JSON.
  def self.parse_error_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  # Checks if Telegram credentials are configured.
  def self.telegram_configured?
    ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
  end
end
