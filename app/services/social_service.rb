# frozen_string_literal: true

# Publishes photos to Facebook and Instagram via Meta Graph API
# on behalf of a Provider. Handles both platforms and records
# the result as a SocialPost.
#
# Usage:
#   SocialService.publish(provider: provider, photo: photo, caption: "¡Trabajo terminado!")
#   # => SocialPost (status: "published" or "failed")
class SocialService
  META_GRAPH_URL = "https://graph.facebook.com/v19.0"

  # Publishes a photo with caption to the provider's connected social accounts.
  # Creates a SocialPost record tracking the result.
  #
  # Returns the created SocialPost record.
  def self.publish(provider:, photo:, caption:)
    new(provider: provider, photo: photo, caption: caption).publish
  end

  def initialize(provider:, photo:, caption:)
    @provider = provider
    @photo = photo
    @caption = caption
  end

  def publish
    return create_failed_post("El proveedor no tiene token de Facebook") unless facebook_connected?

    platform = determine_platform
    errors = []

    errors << publish_to_facebook if publish_to_facebook?(platform)
    errors << publish_to_instagram if publish_to_instagram?(platform)
    errors.compact!

    if errors.empty?
      create_published_post(platform)
    else
      create_failed_post(errors.join("; "), platform)
    end
  end

  private

  def facebook_connected?
    @provider.facebook_token.present?
  end

  def determine_platform
    @provider.instagram_token.present? ? "both" : "facebook"
  end

  def publish_to_facebook?(platform)
    %w[facebook both].include?(platform)
  end

  def publish_to_instagram?(platform)
    %w[instagram both].include?(platform)
  end

  # Posts a photo to the provider's Facebook page.
  # Uses the Page Photos endpoint with the photo URL and caption.
  def publish_to_facebook
    page_id = fetch_page_id
    return "No se pudo obtener el ID de la página de Facebook" unless page_id

    response = HTTParty.post(
      "#{META_GRAPH_URL}/#{page_id}/photos",
      headers: default_headers,
      body: {
        url: @photo.url,
        message: @caption,
        access_token: @provider.facebook_token
      }.to_json
    )

    unless response.success?
      error_message = parse_error(response)
      Rails.logger.error("[SocialService] Facebook publish failed: #{error_message}")
      return "Facebook: #{error_message}"
    end

    nil
  end

  # Posts a photo to Instagram via the Content Publishing API.
  # Two-step process: create media container, then publish it.
  def publish_to_instagram
    ig_account_id = fetch_instagram_account_id
    return "No se pudo obtener la cuenta de Instagram" unless ig_account_id

    # Step 1: Create media container
    container_response = HTTParty.post(
      "#{META_GRAPH_URL}/#{ig_account_id}/media",
      headers: default_headers,
      body: {
        image_url: @photo.url,
        caption: @caption,
        access_token: @provider.instagram_token
      }.to_json
    )

    unless container_response.success?
      error_message = parse_error(container_response)
      Rails.logger.error("[SocialService] Instagram container creation failed: #{error_message}")
      return "Instagram: #{error_message}"
    end

    creation_id = container_response.parsed_response["id"]

    # Step 2: Publish the container
    publish_response = HTTParty.post(
      "#{META_GRAPH_URL}/#{ig_account_id}/media_publish",
      headers: default_headers,
      body: {
        creation_id: creation_id,
        access_token: @provider.instagram_token
      }.to_json
    )

    unless publish_response.success?
      error_message = parse_error(publish_response)
      Rails.logger.error("[SocialService] Instagram publish failed: #{error_message}")
      return "Instagram: #{error_message}"
    end

    nil
  end

  # Fetches the Facebook Page ID associated with the provider's token.
  def fetch_page_id
    response = HTTParty.get(
      "#{META_GRAPH_URL}/me/accounts",
      query: { access_token: @provider.facebook_token }
    )

    return nil unless response.success?

    response.parsed_response.dig("data", 0, "id")
  end

  # Fetches the Instagram Business Account ID linked to the Facebook Page.
  def fetch_instagram_account_id
    page_id = fetch_page_id
    return nil unless page_id

    response = HTTParty.get(
      "#{META_GRAPH_URL}/#{page_id}",
      query: {
        fields: "instagram_business_account",
        access_token: @provider.facebook_token
      }
    )

    return nil unless response.success?

    response.parsed_response.dig("instagram_business_account", "id")
  end

  def create_published_post(platform)
    @provider.social_posts.create!(
      photo: @photo,
      caption_generated: @caption,
      platform: platform,
      status: "published",
      published_at: Time.current
    )
  end

  def create_failed_post(error_message, platform = "facebook")
    @provider.social_posts.create!(
      photo: @photo,
      caption_generated: @caption,
      platform: platform,
      status: "failed",
      error_message: error_message
    )
  end

  def default_headers
    { "Content-Type" => "application/json" }
  end

  def parse_error(response)
    parsed = response.parsed_response
    parsed.dig("error", "message") || "Error HTTP #{response.code}"
  rescue StandardError
    "Error HTTP #{response.code}"
  end
end
