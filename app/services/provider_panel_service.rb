# frozen_string_literal: true

# Loads all data needed to render the provider panel (/mi-perfil).
# Keeps query logic out of controllers and views.
#
# Provides:
#   - Provider profile data (categories, photos)
#   - Monthly metrics (jobs, income, rating, new reviews)
#   - Photo management data (count, limit)
#   - Social media connection status
#   - Assistant config (WhatsApp number, link, auto-reply message)
class ProviderPanelService
  MAX_PHOTOS = 10

  attr_reader :provider, :categories, :primary_category, :profile_photo,
              :work_photos, :metrics, :social_status, :assistant_config

  def initialize(provider)
    @provider = provider
  end

  def self.call(provider)
    new(provider).call
  end

  def call
    load_categories
    load_photos
    build_metrics
    build_social_status
    build_assistant_config
    self
  end

  def photo_slots_remaining
    MAX_PHOTOS - work_photos.size
  end

  def photo_limit_reached?
    work_photos.size >= MAX_PHOTOS
  end

  private

  def load_categories
    @categories = provider.provider_categories.order(primary: :desc, name: :asc)
    @primary_category = @categories.find(&:primary?)
  end

  def load_photos
    photos = provider.photos.order(created_at: :desc)
    @profile_photo = photos.find(&:profile_photo?)
    @work_photos = photos.reject(&:profile_photo?)
  end

  def build_metrics
    current_month_start = Time.current.beginning_of_month
    current_month_end = Time.current.end_of_month

    jobs_this_month = provider.jobs
                              .where(service_date: current_month_start..current_month_end)
                              .count

    income_this_month = provider.transactions
                                .where(transaction_type: "income")
                                .where(recorded_at: current_month_start..current_month_end)
                                .sum(:amount)

    all_reviews = provider.reviews.where(verified: true)
    average_rating = all_reviews.any? ? (all_reviews.average(:rating).to_f.round(1)) : 0.0

    new_reviews = provider.reviews
                          .where(verified: true)
                          .where(created_at: current_month_start..current_month_end)
                          .count

    @metrics = {
      jobs_this_month: jobs_this_month,
      income_this_month: income_this_month,
      average_rating: average_rating,
      new_reviews: new_reviews
    }
  end

  def build_social_status
    @social_status = {
      facebook_connected: provider.facebook_token.present?,
      facebook_page_url: provider.facebook_page_url,
      instagram_linked: provider.instagram_token.present?
    }
  end

  def build_assistant_config
    whatsapp_number = ENV.fetch("TRATO_WHATSAPP_NUMBER", "")
    formatted_number = format_phone_display(whatsapp_number)

    @assistant_config = {
      whatsapp_number: whatsapp_number,
      formatted_number: formatted_number,
      assistant_link: provider.assistant_whatsapp_link,
      short_uuid: provider.short_uuid,
      auto_reply_message: build_auto_reply_message(formatted_number)
    }
  end

  def format_phone_display(number)
    return number if number.length < 10

    # Format: +52 222 123 4567
    "+#{number[0..1]} #{number[2..4]} #{number[5..7]} #{number[8..11]}"
  end

  def build_auto_reply_message(formatted_number)
    "Hola 👋 Gracias por escribirme.\n" \
      "Ahorita estoy trabajando.\n" \
      "Mi asistente puede ayudarte:\n" \
      "#{provider.assistant_whatsapp_link}"
  end
end
