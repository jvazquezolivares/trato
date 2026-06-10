# frozen_string_literal: true

# == Schema Information
#
# Table name: providers
#
#  id                        :bigint       not null, primary key
#  active                    :boolean      default(true)
#  base_price                :string
#  bio                       :text
#  city                      :string
#  email                     :string
#  facebook_page_url         :string
#  facebook_token            :string
#  facebook_token_expires_at :datetime
#  instagram_token           :string
#  name                      :string
#  onboarded_at              :datetime
#  phone                     :string       unique
#  service_area              :text
#  short_uuid                :string       unique
#  slug                      :string       unique
#  created_at                :datetime     not null
#  updated_at                :datetime     not null
#
# Indexes: phone (unique), short_uuid (unique), slug (unique), [city, active]
#
class Provider < ApplicationRecord
  has_many :provider_categories, dependent: :destroy
  has_many :provider_clients, dependent: :destroy
  has_many :clients, through: :provider_clients
  has_many :work_days, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :photos, dependent: :destroy
  has_many :social_posts, dependent: :destroy

  # Computed WhatsApp assistant link — NEVER stored as a DB column.
  # Built dynamically so all links update automatically if the number changes.
  # The message includes the provider name and short_uuid so clients see a clear,
  # personalized message while the system can still identify the provider.
  # Uses the CLIENT number because this link is for clients to contact the provider.
  def assistant_whatsapp_link
    message = "Envía este mensaje para contactar al asistente de #{name} (#{short_uuid})"
    encoded_message = URI.encode_www_form_component(message)
    whatsapp_number = ENV['TRATO_WHATSAPP_CLIENT_NUMBER'] || ENV['TRATO_WHATSAPP_NUMBER']
    "https://wa.me/#{whatsapp_number}?text=#{encoded_message}"
  end

  # Builds the SEO-friendly slug from primary category, city, name, and short_uuid.
  # Format: "{primary_cat_plural}-en-{city}/{name}-{primary_cat}-{short_uuid}"
  def build_slug
    primary_category = provider_categories.detect(&:primary?)
    return unless primary_category

    category_plural = primary_category.slug.pluralize
    city_param = city.parameterize
    name_param = name.parameterize

    "#{category_plural}-en-#{city_param}/#{name_param}-#{primary_category.slug}-#{short_uuid}"
  end
end
