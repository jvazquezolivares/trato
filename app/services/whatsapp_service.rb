# frozen_string_literal: true

# Sends messages via Meta Cloud API (WhatsApp Business).
# Supports single text messages and multi-part sequences with a 1.5s pause.
class WhatsAppService
  BASE_URL = "https://graph.facebook.com/v19.0"

  # Sends a single text message to a WhatsApp recipient.
  def self.send_message(to:, message:)
    url = "#{BASE_URL}/#{ENV['WHATSAPP_PHONE_NUMBER_ID']}/messages"

    response = HTTParty.post(
      url,
      headers: {
        "Authorization" => "Bearer #{ENV['WHATSAPP_ACCESS_TOKEN']}",
        "Content-Type" => "application/json"
      },
      body: {
        messaging_product: "whatsapp",
        to: to,
        type: "text",
        text: { body: message }
      }.to_json
    )

    unless response.success?
      Rails.logger.error(
        "[WhatsAppService] Failed to send message to #{to}: " \
        "HTTP #{response.code} — #{response.body}"
      )
    end

    response
  end

  # Sends multiple messages sequentially with a 1.5-second pause between each.
  # Used for multi-part explanations per assistant tone guidelines.
  def self.send_multipart(to:, messages:)
    messages.each_with_index do |msg, index|
      send_message(to: to, message: msg)
      sleep(1.5) if index < messages.length - 1
    end
  end

  # Sends an interactive List Message to a WhatsApp recipient.
  # Used for presenting 4+ options (Quick Reply Buttons limited to 3).
  #
  # @param to [String] Recipient phone number
  # @param payload [Hash] List Message payload from WhatsApp::ListMessageBuilder
  # @return [HTTParty::Response] API response
  def self.send_list_message(to:, payload:)
    url = "#{BASE_URL}/#{ENV['WHATSAPP_PHONE_NUMBER_ID']}/messages"

    response = HTTParty.post(
      url,
      headers: {
        "Authorization" => "Bearer #{ENV['WHATSAPP_ACCESS_TOKEN']}",
        "Content-Type" => "application/json"
      },
      body: {
        messaging_product: "whatsapp",
        to: to,
        type: "interactive",
        interactive: payload
      }.to_json
    )

    unless response.success?
      Rails.logger.error(
        "[WhatsAppService] Failed to send list message to #{to}: " \
        "HTTP #{response.code} — #{response.body}"
      )
    end

    response
  end
end
