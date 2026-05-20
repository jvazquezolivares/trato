# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_20_044650) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "appointments", force: :cascade do |t|
    t.string "address"
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "estimated_duration", default: 60
    t.string "how_client_arrived"
    t.text "notes"
    t.bigint "provider_id", null: false
    t.datetime "scheduled_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id"
    t.index ["client_id"], name: "index_appointments_on_client_id"
    t.index ["provider_id", "scheduled_at"], name: "index_appointments_on_provider_id_and_scheduled_at"
    t.index ["provider_id"], name: "index_appointments_on_provider_id"
    t.index ["status"], name: "index_appointments_on_status"
    t.index ["work_day_id"], name: "index_appointments_on_work_day_id"
  end

  create_table "clients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "phone"
    t.decimal "rating"
    t.datetime "updated_at", null: false
    t.index ["phone"], name: "index_clients_on_phone", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "client_id"
    t.jsonb "context"
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.string "phone"
    t.bigint "provider_id", null: false
    t.string "role"
    t.string "stage"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_conversations_on_client_id"
    t.index ["phone"], name: "index_conversations_on_phone", unique: true
    t.index ["provider_id", "stage"], name: "index_conversations_on_provider_id_and_stage"
    t.index ["provider_id"], name: "index_conversations_on_provider_id"
  end

  create_table "jobs", force: :cascade do |t|
    t.decimal "amount"
    t.bigint "appointment_id"
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "paid_amount", default: "0.0"
    t.string "payment_method"
    t.bigint "provider_id", null: false
    t.integer "review_attempts", default: 0, null: false
    t.datetime "review_requested_at"
    t.boolean "review_sent", default: false
    t.date "service_date"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_jobs_on_appointment_id"
    t.index ["client_id"], name: "index_jobs_on_client_id"
    t.index ["provider_id", "service_date"], name: "index_jobs_on_provider_id_and_service_date"
    t.index ["provider_id", "status"], name: "index_jobs_on_provider_id_and_status"
    t.index ["provider_id"], name: "index_jobs_on_provider_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "direction"
    t.string "intent"
    t.string "media_url"
    t.boolean "processed", default: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["processed"], name: "index_messages_on_unprocessed", where: "(processed = false)"
  end

  create_table "onboarding_declines", force: :cascade do |t|
    t.jsonb "context"
    t.datetime "created_at", null: false
    t.string "phone", null: false
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_onboarding_declines_on_created_at"
    t.index ["phone"], name: "index_onboarding_declines_on_phone"
  end

  create_table "photos", force: :cascade do |t|
    t.text "caption"
    t.jsonb "category_tags"
    t.datetime "created_at", null: false
    t.bigint "job_id"
    t.integer "position", default: 0
    t.boolean "profile_photo", default: false
    t.bigint "provider_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["job_id"], name: "index_photos_on_job_id"
    t.index ["provider_id"], name: "index_photos_on_provider_id"
  end

  create_table "provider_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.boolean "primary", default: false
    t.bigint "provider_id", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["provider_id", "primary"], name: "index_provider_categories_on_provider_id_and_primary"
    t.index ["provider_id", "slug"], name: "index_provider_categories_on_provider_id_and_slug", unique: true
    t.index ["provider_id"], name: "index_provider_categories_on_provider_id"
  end

  create_table "provider_clients", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_contacted_at"
    t.text "notes"
    t.bigint "provider_id", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_provider_clients_on_client_id"
    t.index ["provider_id", "client_id"], name: "index_provider_clients_on_provider_id_and_client_id", unique: true
    t.index ["provider_id"], name: "index_provider_clients_on_provider_id"
  end

  create_table "providers", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "base_price"
    t.text "bio"
    t.string "city"
    t.datetime "created_at", null: false
    t.string "decline_reason"
    t.string "email"
    t.string "facebook_page_url"
    t.string "facebook_token"
    t.datetime "facebook_token_expires_at"
    t.string "instagram_token"
    t.string "name"
    t.datetime "onboarded_at"
    t.string "phone"
    t.integer "reviews_count", default: 0, null: false
    t.text "service_area"
    t.string "short_uuid"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.integer "years_experience"
    t.index ["city", "active"], name: "index_providers_on_city_and_active"
    t.index ["phone"], name: "index_providers_on_phone", unique: true
    t.index ["short_uuid"], name: "index_providers_on_short_uuid", unique: true
    t.index ["slug"], name: "index_providers_on_slug", unique: true
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "provider_id", null: false
    t.integer "rating"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: true
    t.index ["client_id"], name: "index_reviews_on_client_id"
    t.index ["job_id"], name: "index_reviews_on_job_id", unique: true
    t.index ["provider_id"], name: "index_reviews_on_provider_id"
  end

  create_table "social_posts", force: :cascade do |t|
    t.text "caption_generated"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "photo_id", null: false
    t.string "platform"
    t.bigint "provider_id", null: false
    t.datetime "published_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["photo_id"], name: "index_social_posts_on_photo_id"
    t.index ["provider_id"], name: "index_social_posts_on_provider_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "priority"
    t.bigint "provider_id", null: false
    t.datetime "snoozed_until"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id"
    t.index ["provider_id"], name: "index_tasks_on_provider_id"
    t.index ["work_day_id"], name: "index_tasks_on_work_day_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.decimal "amount"
    t.string "assigned_to"
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "job_id"
    t.string "payment_method"
    t.bigint "provider_id", null: false
    t.datetime "recorded_at"
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_transactions_on_client_id"
    t.index ["job_id"], name: "index_transactions_on_job_id"
    t.index ["provider_id", "recorded_at"], name: "index_transactions_on_provider_id_and_recorded_at"
    t.index ["provider_id", "transaction_type"], name: "index_transactions_on_provider_id_and_transaction_type"
    t.index ["provider_id"], name: "index_transactions_on_provider_id"
  end

  create_table "work_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.time "ends_at"
    t.text "notes"
    t.bigint "provider_id", null: false
    t.time "starts_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["provider_id", "date"], name: "index_work_days_on_provider_id_and_date", unique: true
    t.index ["provider_id"], name: "index_work_days_on_provider_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointments", "clients"
  add_foreign_key "appointments", "providers"
  add_foreign_key "appointments", "work_days"
  add_foreign_key "conversations", "clients"
  add_foreign_key "conversations", "providers"
  add_foreign_key "jobs", "appointments"
  add_foreign_key "jobs", "clients"
  add_foreign_key "jobs", "providers"
  add_foreign_key "messages", "conversations"
  add_foreign_key "photos", "jobs"
  add_foreign_key "photos", "providers"
  add_foreign_key "provider_categories", "providers"
  add_foreign_key "provider_clients", "clients"
  add_foreign_key "provider_clients", "providers"
  add_foreign_key "reviews", "clients"
  add_foreign_key "reviews", "jobs"
  add_foreign_key "reviews", "providers"
  add_foreign_key "social_posts", "photos"
  add_foreign_key "social_posts", "providers"
  add_foreign_key "tasks", "providers"
  add_foreign_key "tasks", "work_days"
  add_foreign_key "transactions", "clients"
  add_foreign_key "transactions", "jobs"
  add_foreign_key "transactions", "providers"
  add_foreign_key "work_days", "providers"
end
