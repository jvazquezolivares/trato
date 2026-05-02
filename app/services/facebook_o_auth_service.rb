# frozen_string_literal: true

# Handles Facebook OAuth logic: connect_token validation, OAuth URL generation,
# token exchange, Instagram auto-linking, and token refresh via Meta Graph API.
#
# The connect_token flow works as follows:
#   1. SocialService generates a connect_token (SecureRandom.hex(16)) and stores
#      it in Redis with a 10-minute TTL keyed as "facebook_connect:{token}" → provider_id
#   2. Provider taps the WhatsApp link: trato.mx/connect/facebook?token={connect_token}
#   3. FacebookOAuthService validates the token, redirects to Facebook OAuth
#   4. On callback, exchanges the code for tokens and saves them on the Provider
#
# Usage:
#   FacebookOAuthService.validate_connect_token(token: "abc123")
#   # => { valid: true, provider: #<Provider> }
#
#   FacebookOAuthService.build_oauth_url(connect_token: "abc123")
#   # => "https://www.facebook.com/v19.0/dialog/oauth?..."
#
#   FacebookOAuthService.exchange_code(code: "...", connect_token: "abc123")
#   # => { success: true, provider: #<Provider> }
#
#   FacebookOAuthService.refresh_expiring_tokens
#   # => refreshes all tokens expiring within 10 days
class FacebookOAuthService
  META_GRAPH_URL = "https://graph.facebook.com/v19.0"
  META_OAUTH_URL = "https://www.facebook.com/v19.0/dialog/oauth"
  REDIS_KEY_PREFIX = "facebook_connect"
  TOKEN_TTL = 600 # 10 minutes
  EXPIRY_WINDOW_DAYS = 10

  # Validates a connect_token from Redis.
  # Returns { valid: true, provider: Provider } or { valid: false, error: :expired }
  def self.validate_connect_token(token:)
    provider_id = REDIS.get(redis_key(token))

    return { valid: false, error: :expired } unless provider_id

    provider = Provider.find_by(id: provider_id)
    return { valid: false, error: :provider_not_found } unless provider

    { valid: true, provider: provider }
  end

  # Builds the Facebook OAuth authorization URL with required permissions.
  # The connect_token is passed as state to retrieve the provider on callback.
  def self.build_oauth_url(connect_token:)
    callback_url = "#{ENV.fetch('APP_URL', 'https://trato.mx')}/connect/facebook/callback"

    params = {
      client_id: ENV.fetch("FACEBOOK_APP_ID"),
      redirect_uri: callback_url,
      state: connect_token,
      scope: "pages_manage_posts,pages_read_engagement,instagram_basic,instagram_content_publish",
      response_type: "code"
    }

    "#{META_OAUTH_URL}?#{params.to_query}"
  end

  # Exchanges the OAuth authorization code for access tokens.
  # Saves facebook_token, facebook_token_expires_at, and auto-links instagram_token.
  # Returns { success: true, provider: Provider } or { success: false, error: String }
  def self.exchange_code(code:, connect_token:)
    validation = validate_connect_token(token: connect_token)
    return { success: false, error: "Token de conexión inválido o expirado" } unless validation[:valid]

    provider = validation[:provider]

    # Exchange short-lived code for short-lived user token
    short_lived_token = fetch_short_lived_token(code)
    return { success: false, error: "No se pudo obtener el token de Facebook" } unless short_lived_token

    # Exchange short-lived token for long-lived token (~60 days)
    long_lived_result = fetch_long_lived_token(short_lived_token)
    return { success: false, error: "No se pudo obtener el token de larga duración" } unless long_lived_result

    # Get page token (long-lived, does not expire)
    page_token = fetch_page_token(long_lived_result[:token])

    # Save tokens on the provider
    token_to_save = page_token || long_lived_result[:token]
    expires_at = page_token ? nil : Time.current + long_lived_result[:expires_in].seconds

    provider.update!(
      facebook_token: token_to_save,
      facebook_token_expires_at: expires_at
    )

    # Auto-link Instagram token
    auto_link_instagram(provider, token_to_save)

    # Clean up the connect_token from Redis
    REDIS.del(redis_key(connect_token))

    { success: true, provider: provider }
  rescue StandardError => e
    Rails.logger.error("[FacebookOAuthService] Token exchange failed: #{e.message}")
    { success: false, error: "Error al conectar Facebook: #{e.message}" }
  end

  # Finds all providers with tokens expiring within 10 days and refreshes them.
  # On failure, notifies the provider via WhatsApp with a new connect link.
  def self.refresh_expiring_tokens
    expiry_threshold = EXPIRY_WINDOW_DAYS.days.from_now

    providers_to_refresh = Provider
      .where(active: true)
      .where.not(facebook_token: nil)
      .where.not(facebook_token_expires_at: nil)
      .where(facebook_token_expires_at: ..expiry_threshold)

    providers_to_refresh.find_each do |provider|
      refresh_token_for(provider)
    end
  end

  # Refreshes a single provider's Facebook token.
  # Returns true on success, false on failure (with WhatsApp notification).
  def self.refresh_token_for(provider)
    result = fetch_long_lived_token(provider.facebook_token)

    if result
      provider.update!(
        facebook_token: result[:token],
        facebook_token_expires_at: Time.current + result[:expires_in].seconds
      )

      auto_link_instagram(provider, result[:token])

      Rails.logger.info(
        "[FacebookOAuthService] Refreshed token for #{provider.name} (#{provider.id})"
      )
      true
    else
      notify_provider_reconnect(provider)
      false
    end
  rescue StandardError => e
    Rails.logger.error(
      "[FacebookOAuthService] Token refresh failed for #{provider.name} (#{provider.id}): #{e.message}"
    )
    notify_provider_reconnect(provider)
    false
  end

  # Generates a new connect_token and sends a reconnect link via WhatsApp.
  # Used when token refresh fails.
  def self.notify_provider_reconnect(provider)
    connect_token = SecureRandom.hex(16)
    REDIS.setex(redis_key(connect_token), TOKEN_TTL, provider.id.to_s)

    app_url = ENV.fetch("APP_URL", "https://trato.mx")
    reconnect_url = "#{app_url}/connect/facebook?token=#{connect_token}"

    WhatsAppService.send_message(
      to: provider.phone,
      message: "Hola #{provider.name} 👋 Tu conexión con Facebook está por vencer. " \
               "Para seguir publicando tus trabajos automáticamente, " \
               "reconecta tu cuenta aquí:\n#{reconnect_url}"
    )
  end

  # --- Private helpers ---

  def self.redis_key(token)
    "#{REDIS_KEY_PREFIX}:#{token}"
  end

  # Exchanges the authorization code for a short-lived user access token.
  def self.fetch_short_lived_token(code)
    callback_url = "#{ENV.fetch('APP_URL', 'https://trato.mx')}/connect/facebook/callback"

    response = HTTParty.get(
      "#{META_GRAPH_URL}/oauth/access_token",
      query: {
        client_id: ENV.fetch("FACEBOOK_APP_ID"),
        client_secret: ENV.fetch("FACEBOOK_APP_SECRET"),
        redirect_uri: callback_url,
        code: code
      }
    )

    return nil unless response.success?

    response.parsed_response["access_token"]
  end

  # Exchanges a short-lived token for a long-lived token (~60 days).
  def self.fetch_long_lived_token(short_lived_token)
    response = HTTParty.get(
      "#{META_GRAPH_URL}/oauth/access_token",
      query: {
        grant_type: "fb_exchange_token",
        client_id: ENV.fetch("FACEBOOK_APP_ID"),
        client_secret: ENV.fetch("FACEBOOK_APP_SECRET"),
        fb_exchange_token: short_lived_token
      }
    )

    return nil unless response.success?

    parsed = response.parsed_response
    {
      token: parsed["access_token"],
      expires_in: parsed["expires_in"] || 5_184_000 # default 60 days
    }
  end

  # Fetches the Page access token (long-lived, does not expire).
  # Returns nil if no pages are found.
  def self.fetch_page_token(user_token)
    response = HTTParty.get(
      "#{META_GRAPH_URL}/me/accounts",
      query: { access_token: user_token }
    )

    return nil unless response.success?

    response.parsed_response.dig("data", 0, "access_token")
  end

  # Auto-links the Instagram Business Account token if available.
  def self.auto_link_instagram(provider, facebook_token)
    page_id = fetch_page_id(facebook_token)
    return unless page_id

    response = HTTParty.get(
      "#{META_GRAPH_URL}/#{page_id}",
      query: {
        fields: "instagram_business_account",
        access_token: facebook_token
      }
    )

    return unless response.success?

    ig_account_id = response.parsed_response.dig("instagram_business_account", "id")
    return unless ig_account_id

    # The same facebook_token works for Instagram API calls on the linked account
    provider.update!(instagram_token: facebook_token)
  end

  # Fetches the Facebook Page ID from the user's pages.
  def self.fetch_page_id(token)
    response = HTTParty.get(
      "#{META_GRAPH_URL}/me/accounts",
      query: { access_token: token }
    )

    return nil unless response.success?

    response.parsed_response.dig("data", 0, "id")
  end

  private_class_method :redis_key, :fetch_short_lived_token, :fetch_long_lived_token,
                       :fetch_page_token, :auto_link_instagram, :fetch_page_id
end
