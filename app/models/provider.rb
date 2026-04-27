# frozen_string_literal: true

# == Schema Information
#
# Table name: providers
#
#  id                        :bigint       not null, primary key
#  active                    :boolean      default(true)
#  base_price                :decimal
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
  def assistant_whatsapp_link
    "https://wa.me/#{ENV['TRATO_WHATSAPP_NUMBER']}?text=#{short_uuid}"
  end

  # Builds the SEO-friendly slug from primary category, city, name, and short_uuid.
  # Format: "{primary_cat_plural}-en-{city}/{name}-{primary_cat}-{short_uuid}"
  def build_slug
    primary_category = provider_categories.find_by(primary: true)
    return unless primary_category

    category_plural = primary_category.slug.pluralize
    city_param = city.parameterize
    name_param = name.parameterize

    "#{category_plural}-en-#{city_param}/#{name_param}-#{primary_category.slug}-#{short_uuid}"
  end
end
