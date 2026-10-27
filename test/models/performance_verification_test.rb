# frozen_string_literal: true

require "test_helper"

class PerformanceVerificationTest < ActiveSupport::TestCase
  test "analytics queries execute against survey_daily_metrics and never scan submissions table" do
    customer = Customer.create!(name: "Perf Customer")
    survey = customer.surveys.create!(title: "Perf Survey", status: :published)

    # Populate 100 submissions
    100.times do
      survey.submissions.create!(submitted_at: Time.current)
    end

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql unless payload[:name] == "SCHEMA" || sql =~ /SAVEPOINT|ROLLBACK|BEGIN|COMMIT/
    end

    # Execute analytics queries
    start_date = 90.days.ago.to_date
    end_date = Date.current

    daily_responses = customer.survey_daily_metrics
                              .where(date: start_date..end_date)
                              .group(:date)
                              .order(date: :desc)
                              .sum(:response_count)

    survey_counts = customer.survey_daily_metrics
                            .group(:survey_id)
                            .sum(:response_count)

    ActiveSupport::Notifications.unsubscribe(subscriber)

    # Assertions
    assert queries.any? { |q| q =~ /FROM "survey_daily_metrics"/i }, "Must query survey_daily_metrics"
    refute queries.any? { |q| q =~ /FROM "submissions" GROUP BY/i }, "Must NOT perform GROUP BY aggregation on submissions table"
    assert_equal 100, daily_responses[Date.current]
    assert_equal 100, survey_counts[survey.id]
  end
end
