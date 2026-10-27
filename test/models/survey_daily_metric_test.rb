# frozen_string_literal: true

require "test_helper"
require "rake"

class SurveyDailyMetricTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("analytics:backfill")

    @customer_a = Customer.create!(name: "Analytics Corp A")
    @customer_b = Customer.create!(name: "Analytics Corp B")

    @survey_a = Survey.create!(
      customer: @customer_a,
      title: "Customer A Survey",
      status: :published,
      published_at: Time.current
    )
    @survey_a.questions.create!(question_text: "Q1", question_type: :text, position: 1)

    @survey_b = Survey.create!(
      customer: @customer_b,
      title: "Customer B Survey",
      status: :published,
      published_at: Time.current
    )
    @survey_b.questions.create!(question_text: "Q1", question_type: :text, position: 1)
  end

  # Test A — Metric creation
  test "test_a_submission_creates_daily_metric_via_job" do
    today = Date.current

    assert_difference -> { SurveyDailyMetric.count }, 1 do
      perform_enqueued_jobs do
        @survey_a.submissions.create!(submitted_at: Time.current)
      end
    end

    metric = SurveyDailyMetric.find_by(survey: @survey_a, date: today)
    assert_not_nil metric
    assert_equal 1, metric.response_count
  end

  # Test B — Multiple submissions on the same day
  test "test_b_multiple_submissions_same_day_accumulate_count" do
    today = Date.current

    perform_enqueued_jobs do
      3.times do
        @survey_a.submissions.create!(submitted_at: Time.current)
      end
    end

    metric = SurveyDailyMetric.find_by(survey: @survey_a, date: today)
    assert_not_nil metric
    assert_equal 3, metric.response_count
    assert_equal 1, SurveyDailyMetric.where(survey: @survey_a, date: today).count
  end

  # Test C — Multiple dates
  test "test_c_submissions_across_multiple_dates_are_bucketed_correctly" do
    d1 = 3.days.ago.to_date
    d2 = 2.days.ago.to_date
    d3 = 1.day.ago.to_date

    perform_enqueued_jobs do
      2.times { @survey_a.submissions.create!(submitted_at: 3.days.ago) }
      4.times { @survey_a.submissions.create!(submitted_at: 2.days.ago) }
      1.times { @survey_a.submissions.create!(submitted_at: 1.day.ago) }
    end

    m1 = SurveyDailyMetric.find_by(survey: @survey_a, date: d1)
    m2 = SurveyDailyMetric.find_by(survey: @survey_a, date: d2)
    m3 = SurveyDailyMetric.find_by(survey: @survey_a, date: d3)

    assert_equal 2, m1.response_count
    assert_equal 4, m2.response_count
    assert_equal 1, m3.response_count
  end

  # Test D — Multiple surveys are isolated
  test "test_d_metrics_are_isolated_per_survey" do
    today = Date.current
    survey_a2 = Survey.create!(customer: @customer_a, title: "Survey A2", status: :published)

    perform_enqueued_jobs do
      2.times { @survey_a.submissions.create!(submitted_at: Time.current) }
      5.times { survey_a2.submissions.create!(submitted_at: Time.current) }
    end

    metric_a1 = SurveyDailyMetric.find_by(survey: @survey_a, date: today)
    metric_a2 = SurveyDailyMetric.find_by(survey: survey_a2, date: today)

    assert_equal 2, metric_a1.response_count
    assert_equal 5, metric_a2.response_count
  end

  # Test E — Multiple customers are isolated
  test "test_e_metrics_remain_strictly_isolated_between_customers" do
    today = Date.current

    perform_enqueued_jobs do
      4.times { @survey_a.submissions.create!(submitted_at: Time.current) }
      7.times { @survey_b.submissions.create!(submitted_at: Time.current) }
    end

    # Scoped via customer associations
    customer_a_total = @customer_a.survey_daily_metrics.where(date: today).sum(:response_count)
    customer_b_total = @customer_b.survey_daily_metrics.where(date: today).sum(:response_count)

    assert_equal 4, customer_a_total
    assert_equal 7, customer_b_total

    # Customer A cannot see Customer B's daily metrics
    refute_includes @customer_a.survey_daily_metrics.pluck(:survey_id), @survey_b.id
  end

  # Test F — Concurrent atomic updates
  test "test_f_concurrent_atomic_upserts_prevent_lost_updates" do
    target_date = Date.new(2026, 10, 27)
    threads = []
    concurrency_count = 10

    # Simulate 10 concurrent threads executing atomic increment
    concurrency_count.times do
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          SurveyDailyMetric.increment_response_count(@survey_a.id, target_date)
        end
      end
    end
    threads.each(&:join)

    metric = SurveyDailyMetric.find_by(survey: @survey_a, date: target_date)
    assert_not_nil metric
    assert_equal concurrency_count, metric.response_count
    assert_equal 1, SurveyDailyMetric.where(survey: @survey_a, date: target_date).count
  end

  # Test G — Backfill task populates metrics
  test "test_g_backfill_task_populates_metrics_from_raw_submissions" do
    # Remove all metrics for clean backfill test
    SurveyDailyMetric.delete_all

    date_a = 5.days.ago.to_date
    date_b = 2.days.ago.to_date

    # Create raw submissions without running jobs
    3.times { Submission.insert!({ survey_id: @survey_a.id, submitted_at: 5.days.ago, created_at: Time.current, updated_at: Time.current }) }
    2.times { Submission.insert!({ survey_id: @survey_b.id, submitted_at: 2.days.ago, created_at: Time.current, updated_at: Time.current }) }

    assert_equal 0, SurveyDailyMetric.count

    Rails.application.load_tasks unless Rake::Task.task_defined?("analytics:backfill")
    Rake::Task["analytics:backfill"].reenable
    Rake::Task["analytics:backfill"].invoke

    metric_a = SurveyDailyMetric.find_by(survey: @survey_a, date: date_a)
    metric_b = SurveyDailyMetric.find_by(survey: @survey_b, date: date_b)

    assert_not_nil metric_a
    assert_equal 3, metric_a.response_count
    assert_not_nil metric_b
    assert_equal 2, metric_b.response_count
  end

  # Test H — Backfill idempotency
  test "test_h_backfill_task_is_strictly_idempotent" do
    Rake::Task["analytics:backfill"].reenable
    Rake::Task["analytics:backfill"].invoke

    count_first_run = SurveyDailyMetric.count

    # Second run
    Rake::Task["analytics:backfill"].reenable
    Rake::Task["analytics:backfill"].invoke

    assert_equal count_first_run, SurveyDailyMetric.count
  end
end
