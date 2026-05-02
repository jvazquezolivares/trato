# frozen_string_literal: true

# Handles OTP generation, storage, and verification for provider login.
#
# OTP codes are stored in Redis with a 10-minute TTL keyed to the provider's phone.
# Only registered providers can receive an OTP — unknown phones are silently rejected.
#
# Usage:
#   result = OtpService.generate(phone: "5212211234567")
#   # => { success: true, masked_phone: "+52 *** ***4567" }
#
#   result = OtpService.verify(phone: "5212211234567", code: "482913")
#   # => { success: true, provider: #<Provider> }
class OtpService
  REDIS_KEY_PREFIX = "otp"
  REDIS_TTL = 600 # 10 minutes
  OTP_LENGTH = 6
  MAX_ATTEMPTS = 5

  # Generates a 6-digit OTP, stores it in Redis, and sends it via WhatsApp.
  # Returns a hash with :success and :masked_phone (for UI display).
  def self.generate(phone:)
    normalized_phone = normalize_phone(phone)
    provider = Provider.find_by(phone: normalized_phone)

    return { success: false, error: :not_found } unless provider

    code = SecureRandom.random_number(10**OTP_LENGTH).to_s.rjust(OTP_LENGTH, "0")

    store_otp(normalized_phone, code)
    send_otp_via_whatsapp(normalized_phone, code)

    { success: true, masked_phone: mask_phone(normalized_phone) }
  end

  # Verifies the OTP code against the stored value in Redis.
  # Returns a hash with :success and :provider on match, or :error on failure.
  def self.verify(phone:, code:)
    normalized_phone = normalize_phone(phone)

    attempts_key = "#{REDIS_KEY_PREFIX}_attempts:#{normalized_phone}"
    attempts = REDIS.get(attempts_key).to_i

    if attempts >= MAX_ATTEMPTS
      return { success: false, error: :max_attempts }
    end

    stored_code = REDIS.get(otp_key(normalized_phone))

    return { success: false, error: :expired } unless stored_code

    unless ActiveSupport::SecurityUtils.secure_compare(stored_code, code.to_s.strip)
      REDIS.setex(attempts_key, REDIS_TTL, (attempts + 1).to_s)
      return { success: false, error: :invalid }
    end

    provider = Provider.find_by(phone: normalized_phone)
    return { success: false, error: :not_found } unless provider

    cleanup_otp(normalized_phone)

    { success: true, provider: provider }
  end

  # --- Private helpers ---

  def self.normalize_phone(phone)
    phone.to_s.gsub(/\D/, "")
  end

  def self.otp_key(phone)
    "#{REDIS_KEY_PREFIX}:#{phone}"
  end

  def self.store_otp(phone, code)
    REDIS.setex(otp_key(phone), REDIS_TTL, code)
  end

  def self.send_otp_via_whatsapp(phone, code)
    WhatsAppService.send_message(
      to: phone,
      message: "Tu código de acceso a Trato es: *#{code}*\n\nNo compartas este código con nadie. Expira en 10 minutos."
    )
  end

  def self.mask_phone(phone)
    return phone if phone.length < 4

    visible_digits = phone[-4..]
    "+52 *** ***#{visible_digits}"
  end

  def self.cleanup_otp(phone)
    REDIS.del(otp_key(phone))
    REDIS.del("#{REDIS_KEY_PREFIX}_attempts:#{phone}")
  end

  private_class_method :normalize_phone, :otp_key, :store_otp,
                       :send_otp_via_whatsapp, :mask_phone, :cleanup_otp
end
