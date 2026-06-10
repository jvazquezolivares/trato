# frozen_string_literal: true

# Sends messages via Meta Cloud API (WhatsApp Business).
# Supports single text messages and multi-part sequences with a 1.5s pause.
class WhatsAppService
  BASE_URL = "https://graph.facebook.com/v19.0"

  # Sends a single text message to a WhatsApp recipient.
  #
  # @param to [String] Recipient phone number
  # @param message [String] Message text content
  # @param phone_number_id [String, nil] Override default phone number ID (defaults to ENV['WHATSAPP_PHONE_NUMBER_ID'])
  # @return [HTTParty::Response] API response
  def self.send_message(to:, message:, phone_number_id: nil)
    phone_id = phone_number_id || ENV["WHATSAPP_PHONE_NUMBER_ID"]
    url = "#{BASE_URL}/#{phone_id}/messages"

    payload = {
      messaging_product: "whatsapp",
      to: to,
      type: "text",
      text: { body: message }
    }

    Rails.logger.info("[WhatsAppService] Sending message to #{to} via phone_id: #{phone_id}")
    Rails.logger.debug("[WhatsAppService] Payload: #{payload.to_json}")

    response = HTTParty.post(
      url,
      headers: {
        "Authorization" => "Bearer #{ENV['WHATSAPP_ACCESS_TOKEN']}",
        "Content-Type" => "application/json"
      },
      body: payload.to_json
    )

    unless response.success?
      Rails.logger.error(
        "[WhatsAppService] Failed to send message to #{to} (phone_id: #{phone_id}): " \
        "HTTP #{response.code} — #{response.body}"
      )
    else
      Rails.logger.info("[WhatsAppService] Successfully sent message to #{to}")
    end

    response
  end

  # Sends multiple messages sequentially with a 1.5-second pause between each.
  # Used for multi-part explanations per assistant tone guidelines.
  #
  # @param to [String] Recipient phone number
  # @param messages [Array<String>] Array of message texts
  # @param phone_number_id [String, nil] Override default phone number ID (defaults to ENV['WHATSAPP_PHONE_NUMBER_ID'])
  def self.send_multipart(to:, messages:, phone_number_id: nil)
    messages.each_with_index do |msg, index|
      send_message(to: to, message: msg, phone_number_id: phone_number_id)
      sleep(1.5) if index < messages.length - 1
    end
  end

  # Sends a message with Quick Reply Buttons (max 3 buttons per WhatsApp API constraint).
  # Used for simple binary or ternary choices.
  #
  # @param to [String] Recipient phone number
  # @param message [String] Message text to display above buttons
  # @param buttons [Array<Hash>] Array of button hashes with :id and :title keys
  #   Example: [{ id: "yes", title: "Sí" }, { id: "no", title: "No" }]
  # @param phone_number_id [String, nil] Override default phone number ID (defaults to ENV['WHATSAPP_PHONE_NUMBER_ID'])
  # @return [HTTParty::Response] API response
  def self.send_message_with_buttons(to:, message:, buttons:, phone_number_id: nil)
    phone_id = phone_number_id || ENV["WHATSAPP_PHONE_NUMBER_ID"]
    url = "#{BASE_URL}/#{phone_id}/messages"

    # Format buttons for Meta Cloud API
    formatted_buttons = buttons.map do |btn|
      {
        type: "reply",
        reply: {
          id: btn[:id],
          title: btn[:title]
        }
      }
    end

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
        interactive: {
          type: "button",
          body: {
            text: message
          },
          action: {
            buttons: formatted_buttons
          }
        }
      }.to_json
    )

    unless response.success?
      Rails.logger.error(
        "[WhatsAppService] Failed to send message with buttons to #{to} (phone_id: #{phone_id}): " \
        "HTTP #{response.code} — #{response.body}"
      )
    end

    response
  end

  # Sends an interactive List Message to a WhatsApp recipient.
  # Used for presenting 4+ options (Quick Reply Buttons limited to 3).
  #
  # @param to [String] Recipient phone number
  # @param payload [Hash] List Message payload from WhatsApp::ListMessageBuilder
  # @param phone_number_id [String, nil] Override default phone number ID (defaults to ENV['WHATSAPP_PHONE_NUMBER_ID'])
  # @return [HTTParty::Response] API response
  def self.send_list_message(to:, payload:, phone_number_id: nil)
    phone_id = phone_number_id || ENV["WHATSAPP_PHONE_NUMBER_ID"]
    url = "#{BASE_URL}/#{phone_id}/messages"

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
        "[WhatsAppService] Failed to send list message to #{to} (phone_id: #{phone_id}): " \
        "HTTP #{response.code} — #{response.body}"
      )
    end

    response
  end

  # Sends a WhatsApp Message Template (pre-approved by Meta).
  # Used for proactive messaging outside the 24-hour messaging window.
  #
  # @param to [String] Recipient phone number
  # @param template_name [String] Name of the approved template (e.g., "morning_summary")
  # @param language [String] Language code (default: "es_MX" for Mexican Spanish)
  # @param parameters [Array<String>] Template parameter values (e.g., [provider.name, summary_text])
  # @param phone_number_id [String, nil] Override default phone number ID (defaults to ENV['WHATSAPP_PHONE_NUMBER_ID'])
  # @return [HTTParty::Response] API response
  #
  # @example Send morning summary template
  #   WhatsAppService.send_template_message(
  #     to: provider.phone,
  #     template_name: "morning_summary",
  #     parameters: [provider.name, "Tienes 3 pendientes de ayer"]
  #   )
  #
  # @example Send review request to client (using client phone number ID)
  #   WhatsAppService.send_template_message(
  #     to: client.phone,
  #     template_name: "review_request",
  #     parameters: [client.name, provider.name, provider.primary_category],
  #     phone_number_id: ENV['WHATSAPP_CLIENT_PHONE_NUMBER_ID']
  #   )
  def self.send_template_message(to:, template_name:, language: "es_MX", parameters: [], phone_number_id: nil)
    phone_id = phone_number_id || ENV["WHATSAPP_PHONE_NUMBER_ID"]
    url = "#{BASE_URL}/#{phone_id}/messages"

    # Build components array with text parameters
    components = if parameters.any?
      [
        {
          type: "body",
          parameters: parameters.map { |param| { type: "text", text: param.to_s } }
        }
      ]
    else
      []
    end

    body_payload = {
      messaging_product: "whatsapp",
      to: to,
      type: "template",
      template: {
        name: template_name,
        language: { code: language },
        components: components
      }
    }

    response = HTTParty.post(
      url,
      headers: {
        "Authorization" => "Bearer #{ENV['WHATSAPP_ACCESS_TOKEN']}",
        "Content-Type" => "application/json"
      },
      body: body_payload.to_json
    )

    if response.success?
      Rails.logger.info(
        "[WhatsAppService] Sent template '#{template_name}' to #{to} " \
        "(phone_id: #{phone_id})"
      )
    else
      Rails.logger.error(
        "[WhatsAppService] Failed to send template '#{template_name}' to #{to}: " \
        "HTTP #{response.code} — #{response.body}"
      )
    end

    response
  end
end
