# frozen_string_literal: true

# Centralizes all business logic for the admin panel.
# Handles dashboard metrics, provider listing/detail, conversation history,
# and financial summaries. Keeps controllers thin and views query-free.
#
# Authentication helpers (OTP generation/verification for admin email)
# are also managed here to keep the AdminController focused on request handling.
class AdminService
  ADMIN_OTP_PREFIX = "admin_otp"
  ADMIN_OTP_TTL = 600 # 10 minutes
  ADMIN_SESSION_KEY = "admin_session"
  OTP_LENGTH = 6

  # --- Authentication ---

  # Validates admin credentials against environment variables.
  # Returns true if both username and password match.
  def self.valid_credentials?(username:, password:)
    expected_username = ENV.fetch("ADMIN_USERNAME", "")
    expected_password = ENV.fetch("ADMIN_PASSWORD", "")

    return false if expected_username.blank? || expected_password.blank?

    ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username) &
      ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)
  end

  # Generates a 6-digit confirmation code, stores it in Redis, and sends it
  # to ADMIN_EMAIL via WhatsApp. Returns the generated code for testing purposes.
  def self.generate_confirmation_code
    code = SecureRandom.random_number(10**OTP_LENGTH).to_s.rjust(OTP_LENGTH, "0")
    REDIS.setex("#{ADMIN_OTP_PREFIX}:code", ADMIN_OTP_TTL, code)
    REDIS.del("#{ADMIN_OTP_PREFIX}:attempts")

    send_confirmation_code(code)
    code
  end

  # Verifies the confirmation code against the stored value in Redis.
  # Returns { success: true } or { success: false, error: :reason }.
  def self.verify_confirmation_code(code:)
    max_attempts = 5
    attempts_key = "#{ADMIN_OTP_PREFIX}:attempts"
    attempts = REDIS.get(attempts_key).to_i

    return { success: false, error: :max_attempts } if attempts >= max_attempts

    stored_code = REDIS.get("#{ADMIN_OTP_PREFIX}:code")
    return { success: false, error: :expired } unless stored_code

    unless ActiveSupport::SecurityUtils.secure_compare(stored_code, code.to_s.strip)
      REDIS.setex(attempts_key, ADMIN_OTP_TTL, (attempts + 1).to_s)
      return { success: false, error: :invalid }
    end

    REDIS.del("#{ADMIN_OTP_PREFIX}:code")
    REDIS.del(attempts_key)

    { success: true }
  end

  # --- Dashboard ---

  # Returns a hash with all dashboard metrics:
  # active_providers, conversations_today, jobs_this_month, estimated_monthly_cost
  def self.dashboard_stats
    {
      active_providers: active_provider_count,
      conversations_today: conversations_today_count,
      jobs_this_month: jobs_this_month_count,
      estimated_monthly_cost: estimated_monthly_cost
    }
  end

  # Returns recent activity items for the dashboard feed.
  # Combines recent jobs, new providers, and escalated conversations.
  def self.recent_activity(limit: 10)
    activities = []

    # Recent jobs registered
    recent_jobs = Job.includes(:provider, :client)
                     .order(created_at: :desc)
                     .limit(limit)

    recent_jobs.each do |job|
      activities << {
        type: :job,
        icon: "assignment_turned_in",
        color: "text-teal-600",
        title: "#{job.provider.name} registró un trabajo",
        description: "#{job.description&.truncate(80)} — $#{job.amount&.to_i} MXN",
        timestamp: job.created_at
      }
    end

    # Recent provider registrations
    recent_providers = Provider.where.not(onboarded_at: nil)
                               .order(onboarded_at: :desc)
                               .limit(5)

    recent_providers.each do |provider|
      primary_cat = provider.provider_categories.find_by(primary: true)
      activities << {
        type: :new_provider,
        icon: "person_add",
        color: "text-amber-600",
        title: "Nuevo proveedor registrado",
        description: "#{provider.name} se unió como #{primary_cat&.name || 'técnico'}",
        timestamp: provider.onboarded_at
      }
    end

    activities.sort_by { |a| a[:timestamp] || Time.at(0) }.reverse.first(limit)
  end

  # Returns provider status breakdown for the donut chart.
  def self.provider_status_breakdown
    total = Provider.count
    active = Provider.where(active: true).count
    inactive = total - active

    {
      total: total,
      active: active,
      inactive: inactive,
      active_percentage: total.positive? ? ((active.to_f / total) * 100).round(1) : 0,
      inactive_percentage: total.positive? ? ((inactive.to_f / total) * 100).round(1) : 0
    }
  end

  # --- Providers ---

  # Returns paginated list of providers with eager-loaded associations.
  # Supports filtering by status (active/inactive), city, and search query.
  def self.providers_list(params = {})
    scope = Provider.includes(:provider_categories, :reviews)

    scope = filter_providers_by_status(scope, params[:status])
    scope = filter_providers_by_city(scope, params[:city])
    scope = filter_providers_by_search(scope, params[:search])

    scope.order(created_at: :desc)
  end

  # Returns detailed data for a single provider including financial summary,
  # recent conversations, and recent jobs.
  def self.provider_detail(provider_id)
    provider = Provider.includes(:provider_categories).find_by(id: provider_id)

    return nil unless provider

    {
      provider: provider,
      financial_summary: provider_financial_summary(provider),
      recent_conversations: provider_recent_conversations(provider),
      recent_jobs: provider_recent_jobs(provider)
    }
  end

  # --- Conversations ---

  # Returns paginated list of conversations with eager-loaded associations.
  # Supports filtering by provider, stage, and date range.
  def self.conversations_list(params = {})
    scope = Conversation.includes(:provider, :messages)

    scope = scope.where(provider_id: params[:provider_id]) if params[:provider_id].present?
    scope = scope.where(stage: params[:stage]) if params[:stage].present?

    if params[:date_from].present?
      scope = scope.where("last_message_at >= ?", params[:date_from].to_date.beginning_of_day)
    end

    if params[:date_to].present?
      scope = scope.where("last_message_at <= ?", params[:date_to].to_date.end_of_day)
    end

    scope.order(last_message_at: :desc)
  end

  # Returns full message history for a conversation.
  def self.conversation_detail(conversation_id)
    conversation = Conversation.includes(:provider, :client).find_by(id: conversation_id)

    return nil unless conversation

    {
      conversation: conversation,
      messages: conversation.messages.order(created_at: :asc),
      provider: conversation.provider,
      client: conversation.client
    }
  end

  # --- Finances ---

  # Returns platform-wide financial summary for the current month.
  def self.financial_summary
    current_month = Time.current.beginning_of_month..Time.current.end_of_month

    platform_income = Transaction.where(transaction_type: "income", recorded_at: current_month).sum(:amount)
    platform_expenses = Transaction.where(transaction_type: "expense", recorded_at: current_month).sum(:amount)
    total_providers = Provider.count
    active_providers = Provider.where(active: true).count

    {
      platform_income: platform_income,
      platform_expenses: platform_expenses.abs,
      net_revenue: platform_income - platform_expenses.abs,
      total_providers: total_providers,
      active_providers: active_providers,
      estimated_infrastructure_cost: estimated_monthly_cost
    }
  end

  # Returns per-provider financial breakdown for the finances table.
  def self.providers_financial_list
    Provider.includes(:transactions, :jobs)
            .where(active: true)
            .order(:name)
            .map do |provider|
              current_month = Time.current.beginning_of_month..Time.current.end_of_month
              income = provider.transactions.where(transaction_type: "income", recorded_at: current_month).sum(:amount)
              jobs_count = provider.jobs.where(service_date: current_month).count

              {
                provider: provider,
                income_this_month: income,
                jobs_this_month: jobs_count
              }
            end
  end

  # --- Private helpers ---

  def self.active_provider_count
    Provider.where(active: true).count
  end

  def self.conversations_today_count
    Conversation.where("last_message_at >= ?", Time.current.beginning_of_day).count
  end

  def self.jobs_this_month_count
    Job.where(service_date: Time.current.beginning_of_month..Time.current.end_of_month).count
  end

  # Estimates monthly infrastructure cost based on message volume and API usage.
  # Meta Cloud API: ~$0.06 MXN per proactive message
  # Claude API: estimated based on conversation count
  def self.estimated_monthly_cost
    current_month = Time.current.beginning_of_month..Time.current.end_of_month
    message_count = Message.where(created_at: current_month).count
    conversation_count = Conversation.where("last_message_at >= ?", Time.current.beginning_of_month).count

    whatsapp_cost = message_count * 0.06
    claude_cost = conversation_count * 0.50
    infrastructure_cost = 500 # Railway base cost estimate in MXN

    (whatsapp_cost + claude_cost + infrastructure_cost).round(2)
  end

  def self.provider_financial_summary(provider)
    current_month = Time.current.beginning_of_month..Time.current.end_of_month

    income = provider.transactions.where(transaction_type: "income", recorded_at: current_month).sum(:amount)
    pending = provider.jobs.where(status: %w[pending partial]).sum("amount - paid_amount")
    expenses = provider.transactions.where(transaction_type: "expense", recorded_at: current_month).sum(:amount)
    jobs_count = provider.jobs.where(service_date: current_month).count

    { income: income, pending: pending, expenses: expenses.abs, jobs_count: jobs_count }
  end

  def self.provider_recent_conversations(provider)
    provider.conversations
            .includes(:client, :messages)
            .order(last_message_at: :desc)
            .limit(5)
  end

  def self.provider_recent_jobs(provider)
    provider.jobs
            .includes(:client)
            .order(created_at: :desc)
            .limit(5)
  end

  def self.filter_providers_by_status(scope, status)
    case status
    when "active" then scope.where(active: true)
    when "inactive" then scope.where(active: false)
    else scope
    end
  end

  def self.filter_providers_by_city(scope, city)
    return scope if city.blank?

    scope.where(city: city)
  end

  def self.filter_providers_by_search(scope, search)
    return scope if search.blank?

    scope.where("providers.name ILIKE :q OR providers.phone ILIKE :q OR providers.short_uuid ILIKE :q",
                q: "%#{search}%")
  end

  def self.send_confirmation_code(code)
    admin_email = ENV.fetch("ADMIN_EMAIL", "")
    return if admin_email.blank?

    # Send confirmation code via WhatsApp to the admin's number
    # In production, this could also be sent via email
    WhatsAppService.send_message(
      to: admin_email,
      message: "🔐 Código de acceso al panel de administración de Trato: *#{code}*\n\nExpira en 10 minutos."
    )
  end

  private_class_method :active_provider_count, :conversations_today_count,
                       :jobs_this_month_count, :estimated_monthly_cost,
                       :provider_financial_summary, :provider_recent_conversations,
                       :provider_recent_jobs, :filter_providers_by_status,
                       :filter_providers_by_city, :filter_providers_by_search,
                       :send_confirmation_code
end
