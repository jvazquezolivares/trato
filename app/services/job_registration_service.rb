# frozen_string_literal: true

# Handles the 5 job registration cases from the ProviderAssistant flow.
# Delegates client lookup to ClientLookupService and creates Job + Transaction
# records based on the payment scenario.
#
# Cases:
#   1. Known client, full payment   → Job(paid) + Transaction(income) + ReviewRequestJob
#   2. Unknown client                → Client creation + Job + Transaction + ReviewRequestJob
#   3. Partial payment               → Job(partial) + Transaction(paid amount) + ReviewRequestJob
#   4. No payment received           → Job(pending)
#   5. Material expense              → Transaction(expense)
#
# Always uses `transaction_type` (never `type`) to avoid Rails STI conflicts.
class JobRegistrationService
  def self.call(provider:, action:, action_data:)
    new(provider: provider, action: action, action_data: action_data).execute
  end

  def initialize(provider:, action:, action_data:)
    @provider = provider
    @action = action
    @data = action_data || {}
  end

  def execute
    case @action
    when "register_job"
      register_job
    when "register_expense"
      register_expense
    end
  end

  private

  # --- Job registration (cases 1-4) ---

  def register_job
    client = resolve_client
    return unless client

    job = create_job(client)
    create_income_transaction(job, client) if job.paid_amount.positive?
    enqueue_review_request(job) if reviewable_status?(job)

    job
  end

  def resolve_client
    phone = @data["client_phone"]
    name = @data["client_name"]

    ClientLookupService.call(
      phone: phone,
      name: name,
      provider: @provider
    )
  end

  def create_job(client)
    Job.create!(
      provider: @provider,
      client: client,
      description: @data["description"],
      amount: parse_decimal(@data["amount"]),
      paid_amount: parse_decimal(@data["paid_amount"]),
      status: determine_job_status,
      payment_method: @data["payment_method"] || "pending",
      service_date: @data["service_date"] || Date.current
    )
  end

  def determine_job_status
    amount = parse_decimal(@data["amount"])
    paid = parse_decimal(@data["paid_amount"])

    return "pending" if paid.zero?
    return "paid" if paid >= amount

    "partial"
  end

  def create_income_transaction(job, client)
    Transaction.create!(
      provider: @provider,
      job: job,
      client: client,
      amount: job.paid_amount,
      transaction_type: "income",
      description: job.description,
      payment_method: job.payment_method,
      recorded_at: Time.current,
      assigned_to: job.id.to_s
    )
  end

  def reviewable_status?(job)
    %w[paid partial].include?(job.status)
  end

  # Schedules the review request at 11am CDMX on the first eligible day
  # after a 24-hour window from now (job completion time).
  def enqueue_review_request(job)
    delivery_time = ReviewRequestJob.calculate_delivery_time(Time.current)
    ReviewRequestJob.set(wait_until: delivery_time).perform_later(job.id)
  end

  # --- Expense registration (case 5) ---

  def register_expense
    job = find_associated_job

    Transaction.create!(
      provider: @provider,
      job: job,
      client: job&.client,
      amount: parse_decimal(@data["amount"]),
      transaction_type: "expense",
      description: @data["description"],
      payment_method: @data["payment_method"] || "cash",
      recorded_at: Time.current,
      assigned_to: job ? job.id.to_s : "general"
    )
  end

  def find_associated_job
    job_id = @data["job_id"]
    return nil unless job_id.present?

    @provider.jobs.find_by(id: job_id)
  end

  # --- Helpers ---

  def parse_decimal(value)
    return BigDecimal("0") if value.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError
    BigDecimal("0")
  end
end
