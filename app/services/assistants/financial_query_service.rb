# frozen_string_literal: true

module Assistants
  # Computes financial data for a Provider based on their Transaction
  # and Job records. Uses a flexible date-range approach so the provider
  # can ask about any period (today, this week, custom range, etc.).
  #
  # Called by ProviderAssistant in a two-step flow:
  #   1. Claude detects a financial query and returns action_data with
  #      query_type + date_from + date_to
  #   2. This service computes the real data
  #   3. ProviderAssistant makes a second Claude call to present the
  #      data conversationally — Claude never invents numbers
  #
  # Query types:
  #   - earnings:    income transactions in a date range
  #   - expenses:    expense transactions in a date range
  #   - outstanding: pending/partial jobs grouped by client (no date range)
  #   - summary:     income - expenses + outstanding for a date range
  #
  # Usage:
  #   Assistants::FinancialQueryService.call(
  #     provider: provider,
  #     query_type: "earnings",
  #     date_from: "2026-04-27",
  #     date_to: "2026-05-01"
  #   )
  class FinancialQueryService
    MEXICO_CITY_TZ = "America/Mexico_City"

    QUERY_TYPES = %w[earnings expenses outstanding summary].freeze

    def self.call(provider:, query_type:, date_from: nil, date_to: nil)
      new(provider: provider, query_type: query_type, date_from: date_from, date_to: date_to).execute
    end

    def initialize(provider:, query_type:, date_from: nil, date_to: nil)
      @provider = provider
      @query_type = query_type
      @date_from = parse_date(date_from)
      @date_to = parse_date(date_to)
    end

    def execute
      return error_response("Tipo de consulta no reconocido") unless valid_query_type?
      return error_response("Se requiere rango de fechas para esta consulta") if requires_dates? && dates_missing?

      send(:"compute_#{@query_type}")
    end

    private

    def valid_query_type?
      QUERY_TYPES.include?(@query_type)
    end

    def requires_dates?
      @query_type != "outstanding"
    end

    def dates_missing?
      @date_from.nil? || @date_to.nil?
    end

    def error_response(message)
      { "error" => message }
    end

    def date_range
      @date_from.beginning_of_day..@date_to.end_of_day
    end

    # --- Earnings (Requirement 10.1, 10.3) ---

    # Sum of income Transactions in the given date range.
    def compute_earnings
      income = sum_transactions("income")

      job_count = @provider.transactions
                           .where(transaction_type: "income")
                           .where(recorded_at: date_range)
                           .distinct
                           .count(:job_id)

      {
        "query_type" => "earnings",
        "income" => income.to_f,
        "job_count" => job_count,
        "date_from" => @date_from.to_s,
        "date_to" => @date_to.to_s
      }
    end

    # --- Expenses (Requirement 10.4) ---

    # Sum of expense Transactions in the given date range,
    # with itemized details (last 10).
    def compute_expenses
      total = sum_transactions("expense")

      details = @provider.transactions
                         .where(transaction_type: "expense")
                         .where(recorded_at: date_range)
                         .order(recorded_at: :desc)
                         .limit(10)
                         .pluck(:description, :amount, :recorded_at)

      items = details.map do |description, amount, recorded_at|
        {
          "description" => description,
          "amount" => amount.to_f,
          "date" => recorded_at&.in_time_zone(MEXICO_CITY_TZ)&.strftime("%A %d de %B")
        }
      end

      {
        "query_type" => "expenses",
        "total_expenses" => total.to_f,
        "expense_count" => details.size,
        "expenses" => items,
        "date_from" => @date_from.to_s,
        "date_to" => @date_to.to_s
      }
    end

    # --- Outstanding amounts (Requirement 10.2) ---

    # Jobs with status pending or partial, grouped by client.
    # No date range needed — this is current state.
    def compute_outstanding
      outstanding_jobs = @provider.jobs
                                  .includes(:client)
                                  .where(status: %w[pending partial])
                                  .order(service_date: :desc)

      grouped = outstanding_jobs.group_by(&:client)

      clients_data = grouped.map do |client, jobs|
        total_owed = jobs.sum { |job| job.amount - job.paid_amount }
        {
          "client_name" => client&.name || "Sin nombre",
          "client_phone" => client&.phone,
          "total_owed" => total_owed.to_f,
          "jobs" => jobs.map do |job|
            {
              "description" => job.description,
              "amount" => job.amount.to_f,
              "paid_amount" => job.paid_amount.to_f,
              "outstanding" => (job.amount - job.paid_amount).to_f,
              "status" => job.status,
              "service_date" => job.service_date&.to_s
            }
          end
        }
      end

      total_outstanding = clients_data.sum { |c| c["total_owed"] }

      {
        "query_type" => "outstanding",
        "total_outstanding" => total_outstanding,
        "client_count" => clients_data.size,
        "clients" => clients_data
      }
    end

    # --- Summary (Requirement 10.3) ---

    # Full financial summary for a date range: income, expenses,
    # net, job count, and outstanding collections.
    def compute_summary
      income = sum_transactions("income")
      expenses = sum_transactions("expense")

      job_count = @provider.jobs
                           .where(service_date: @date_from..@date_to)
                           .count

      outstanding = @provider.jobs
                             .where(status: %w[pending partial])
                             .sum("amount - paid_amount")

      {
        "query_type" => "summary",
        "income" => income.to_f,
        "expenses" => expenses.to_f,
        "net" => (income - expenses).to_f,
        "job_count" => job_count,
        "outstanding_collections" => outstanding.to_f,
        "date_from" => @date_from.to_s,
        "date_to" => @date_to.to_s
      }
    end

    # --- Helpers ---

    def sum_transactions(type)
      @provider.transactions
               .where(transaction_type: type)
               .where(recorded_at: date_range)
               .sum(:amount)
    end

    def parse_date(value)
      return nil if value.blank?
      return value if value.is_a?(Date)

      Date.parse(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end
  end
end
