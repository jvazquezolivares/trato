# frozen_string_literal: true

# Feature: trato-mvp, Property 7: ReviewRequestJob always schedules at 11am CDMX after 24h window
# **Validates: Requirements 6.1, 11.1**
#
# For any Job marked paid or partial at any timestamp, the ReviewRequestJob
# delivery time SHALL always be at 11:00 am Mexico City time AND SHALL always
# be strictly more than 24 hours after the job completion timestamp.

require "rails_helper"

RSpec.describe ReviewRequestJob, "P7: scheduling at 11am CDMX after 24h window", type: :property do
  # Source timezones to generate completion timestamps from different origins
  SOURCE_TIMEZONES = [
    "UTC",
    "America/New_York",
    "America/Chicago",
    "America/Los_Angeles",
    "America/Mexico_City",
    "Europe/London",
    "Asia/Tokyo"
  ].freeze

  # Years to test (2025-2026 covers DST transitions)
  TEST_YEARS = (2025..2026).to_a.freeze

  context "when given random completion timestamps" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "schedules delivery at exactly 11:00 am CDMX, strictly after 24h (iteration #{iteration + 1})" do
        # Generate a random completion timestamp
        year = TEST_YEARS.sample
        month = rand(1..12)
        max_day = Date.new(year, month, -1).day
        day = rand(1..max_day)
        hour = rand(0..23)
        minute = rand(0..59)
        second = rand(0..59)
        source_tz = ActiveSupport::TimeZone[SOURCE_TIMEZONES.sample]

        completed_at = source_tz.local(year, month, day, hour, minute, second)

        delivery_time = ReviewRequestJob.calculate_delivery_time(completed_at)

        # 1. Delivery time must be at exactly 11:00:00 am
        expect(delivery_time.hour).to eq(11),
          "Expected hour=11 but got #{delivery_time.hour} for completed_at=#{completed_at.iso8601}"
        expect(delivery_time.min).to eq(0),
          "Expected min=0 but got #{delivery_time.min} for completed_at=#{completed_at.iso8601}"
        expect(delivery_time.sec).to eq(0),
          "Expected sec=0 but got #{delivery_time.sec} for completed_at=#{completed_at.iso8601}"

        # 2. Delivery time must be in Mexico City timezone
        expect(delivery_time.time_zone.name).to eq("America/Mexico_City"),
          "Expected timezone America/Mexico_City but got #{delivery_time.time_zone.name}"

        # 3. Delivery time must be strictly more than 24 hours after completion
        hours_difference = (delivery_time - completed_at) / 1.hour
        expect(hours_difference).to be > 24,
          "Expected >24h gap but got #{hours_difference.round(2)}h " \
          "for completed_at=#{completed_at.iso8601}, delivery=#{delivery_time.iso8601}"
      end
    end
  end

  context "when completion falls near DST transitions in Mexico" do
    # Mexico observes DST: spring forward in April, fall back in October
    dst_edge_cases = [
      { month: 4, desc: "spring forward (April)" },
      { month: 10, desc: "fall back (October)" }
    ]

    dst_edge_cases.each do |edge_case|
      PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
        it "handles #{edge_case[:desc]} correctly (iteration #{iteration + 1})" do
          year = TEST_YEARS.sample
          max_day = Date.new(year, edge_case[:month], -1).day
          day = rand(1..max_day)
          hour = rand(0..23)
          source_tz = ActiveSupport::TimeZone[SOURCE_TIMEZONES.sample]

          completed_at = source_tz.local(year, edge_case[:month], day, hour, rand(0..59), rand(0..59))

          delivery_time = ReviewRequestJob.calculate_delivery_time(completed_at)

          expect(delivery_time.hour).to eq(11)
          expect(delivery_time.min).to eq(0)
          expect(delivery_time.sec).to eq(0)
          expect(delivery_time.time_zone.name).to eq("America/Mexico_City")

          hours_difference = (delivery_time - completed_at) / 1.hour
          expect(hours_difference).to be > 24,
            "Expected >24h gap but got #{hours_difference.round(2)}h during #{edge_case[:desc]} " \
            "for completed_at=#{completed_at.iso8601}, delivery=#{delivery_time.iso8601}"
        end
      end
    end
  end

  context "when completion is exactly at 11:00 am CDMX (boundary case)" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "never delivers at the exact 24h mark (iteration #{iteration + 1})" do
        mexico_city = ActiveSupport::TimeZone["America/Mexico_City"]
        year = TEST_YEARS.sample
        month = rand(1..12)
        max_day = Date.new(year, month, -1).day
        day = rand(1..max_day)

        # Complete at exactly 11:00 am CDMX — the 24h mark would be next day 11am
        completed_at = mexico_city.local(year, month, day, 11, 0, 0)

        delivery_time = ReviewRequestJob.calculate_delivery_time(completed_at)

        # Should NOT be next day 11am (that's exactly 24h), must be day after
        expect(delivery_time.hour).to eq(11)
        expect(delivery_time.min).to eq(0)
        expect(delivery_time.sec).to eq(0)
        expect(delivery_time.time_zone.name).to eq("America/Mexico_City")

        hours_difference = (delivery_time - completed_at) / 1.hour
        expect(hours_difference).to be > 24,
          "Expected >24h but got exactly #{hours_difference.round(2)}h — " \
          "must never deliver at the exact 24h mark"
      end
    end
  end
end
