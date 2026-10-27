# frozen_string_literal: true

require "test_helper"
require "rake"

class Requirement4AnalyticsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("analytics:backfill")

    # Customer A setup
    @customer_a = Customer.create!(name: "Alpha Corp")
    @user_a = @customer_a.users.create!(
      name: "Alice Alpha",
      email: "alice@alphacorp.test",
      password: "ChangeMe123!"
    )

    # Customer A Surveys
    @survey_a1 = @customer_a.surveys.create!(
      title: "Alpha CSAT Survey",
      status: :published,
      published_at: 90.days.ago
    )
    @q_a1 = @survey_a1.questions.create!(
      question_text: "Rate your satisfaction",
      question_type: :multiple_choice,
      position: 1,
      required: true
    )
    @opt_a1 = @q_a1.question_options.create!(label: "Excellent", position: 1)

    @survey_a2 = @customer_a.surveys.create!(
      title: "Alpha NPS Survey",
      status: :published,
      published_at: 45.days.ago
    )
    @q_a2 = @survey_a2.questions.create!(
      question_text: "How likely are you to recommend us?",
      question_type: :number,
      position: 1,
      required: true
    )

    # Customer B setup (Tenant Isolation)
    @customer_b = Customer.create!(name: "Beta Inc")
    @user_b = @customer_b.users.create!(
      name: "Bob Beta",
      email: "bob@betainc.test",
      password: "ChangeMe123!"
    )

    @survey_b = @customer_b.surveys.create!(
      title: "Beta Feedback Survey",
      status: :published,
      published_at: 60.days.ago
    )
    @q_b = @survey_b.questions.create!(
      question_text: "Feedback notes",
      question_type: :text,
      position: 1,
      required: false
    )
  end

  # =========================================================================
  # 1. Authentication & Route Tests
  # =========================================================================

  test "unauthenticated visitor is redirected to login" do
    get analytics_path
    assert_redirected_to login_path
    follow_redirect!
    assert_includes response.body, "You must log in to access this page."
  end

  test "authenticated user can access analytics dashboard" do
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success
    assert_includes response.body, "Alpha Corp Analytics"
    assert_includes response.body, "Total 90-Day Responses"
    assert_includes response.body, "Active Response Days"
    assert_includes response.body, "Daily Average"
    assert_includes response.body, "Peak Activity Day"
  end

  # =========================================================================
  # 2. Daily Aggregation & Numerical Accuracy Tests
  # =========================================================================

  test "daily response counts match database records accurately" do
    date1 = 3.days.ago.to_date
    date2 = 2.days.ago.to_date
    date3 = 1.day.ago.to_date

    perform_enqueued_jobs do
      2.times { @survey_a1.submissions.create!(submitted_at: 3.days.ago) }
      4.times { @survey_a1.submissions.create!(submitted_at: 2.days.ago) }
      1.times { @survey_a1.submissions.create!(submitted_at: 1.day.ago) }
    end

    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    # Stats cards
    assert_includes response.body, "7" # Total responses
    assert_includes response.body, "3" # Active response days
    assert_includes response.body, "4" # Peak day count

    # Table rows
    assert_includes response.body, date1.strftime("%Y-%m-%d")
    assert_includes response.body, date2.strftime("%Y-%m-%d")
    assert_includes response.body, date3.strftime("%Y-%m-%d")
  end

  # =========================================================================
  # 3. Multi-Survey Customer Aggregation Tests
  # =========================================================================

  test "multiple surveys aggregate correctly under the customer on the same date" do
    target_date = 4.days.ago.to_date

    perform_enqueued_jobs do
      3.times { @survey_a1.submissions.create!(submitted_at: 4.days.ago) }
      2.times { @survey_a2.submissions.create!(submitted_at: 4.days.ago) }
    end

    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    # Daily aggregation should sum to 5 (3 + 2)
    daily_metric = @customer_a.survey_daily_metrics.where(date: target_date).sum(:response_count)
    assert_equal 5, daily_metric

    # Response HTML contains the aggregated count of 5
    assert_includes response.body, target_date.strftime("%Y-%m-%d")
    assert_includes response.body, "5"

    # Per-survey summary table includes both surveys with their individual counts
    assert_includes response.body, "Alpha CSAT Survey"
    assert_includes response.body, "Alpha NPS Survey"
    assert_includes response.body, "3</strong> responses"
    assert_includes response.body, "2</strong> responses"
  end

  # =========================================================================
  # 4. Date Ordering Tests
  # =========================================================================

  test "daily analytics table displays dates in reverse chronological order" do
    d_recent = 1.day.ago.to_date
    d_mid = 5.days.ago.to_date
    d_old = 15.days.ago.to_date

    perform_enqueued_jobs do
      @survey_a1.submissions.create!(submitted_at: 15.days.ago)
      @survey_a1.submissions.create!(submitted_at: 1.day.ago)
      @survey_a1.submissions.create!(submitted_at: 5.days.ago)
    end

    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    pos_recent = response.body.index(d_recent.strftime("%Y-%m-%d"))
    pos_mid = response.body.index(d_mid.strftime("%Y-%m-%d"))
    pos_old = response.body.index(d_old.strftime("%Y-%m-%d"))

    assert_not_nil pos_recent
    assert_not_nil pos_mid
    assert_not_nil pos_old

    # Newest date must appear first in HTML table
    assert pos_recent < pos_mid, "1.day.ago must appear before 5.days.ago"
    assert pos_mid < pos_old, "5.days.ago must appear before 15.days.ago"
  end

  # =========================================================================
  # 5. Zero-Response Days & Timeline Chart Tests
  # =========================================================================

  test "zero-response days are handled safely without carrying forward counts" do
    d_active = 2.days.ago.to_date
    d_zero = 3.days.ago.to_date

    perform_enqueued_jobs do
      3.times { @survey_a1.submissions.create!(submitted_at: 2.days.ago) }
    end

    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    # Active day appears in table
    assert_includes response.body, d_active.strftime("%Y-%m-%d")

    # Zero day does not appear as an active table entry with false count
    # Timeline renders all 90 days safely
    assert_includes response.body, "Daily Response Volume (Past 90 Days)"
    assert_includes response.body, "#{d_zero.strftime('%b %d, %Y')}: 0 responses"
  end

  # =========================================================================
  # 6. Date Range Boundary Tests (Last 90 Days)
  # =========================================================================

  test "analytics strictly respects 90-day window and excludes older submissions" do
    perform_enqueued_jobs do
      @survey_a1.submissions.create!(submitted_at: 10.days.ago)
      @survey_a1.submissions.create!(submitted_at: 89.days.ago)
      @survey_a1.submissions.create!(submitted_at: 95.days.ago) # Older than 90 days
    end

    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    # Total 90-day responses should be 2, not 3
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">2</div>"

    d_old = 95.days.ago.to_date
    refute_includes response.body, d_old.strftime("%Y-%m-%d")
  end

  # =========================================================================
  # 7. Strict Multi-Tenant Isolation Tests
  # =========================================================================

  test "customer A cannot see Customer B metrics and vice versa" do
    perform_enqueued_jobs do
      3.times { @survey_a1.submissions.create!(submitted_at: Time.current) }
      8.times { @survey_b.submissions.create!(submitted_at: Time.current) }
    end

    # Customer A view
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    assert_includes response.body, "Alpha Corp Analytics"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">3</div>"
    refute_includes response.body, "Beta Inc"
    refute_includes response.body, "Beta Feedback Survey"
    refute_includes response.body, ">8</span>"

    # Customer B view
    delete logout_path
    sign_in_as(@user_b)
    get analytics_path
    assert_response :success

    assert_includes response.body, "Beta Inc Analytics"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">8</div>"
    refute_includes response.body, "Alpha Corp"
    refute_includes response.body, "Alpha CSAT Survey"

    # Parameter tampering attempt: Customer A passes Customer B's survey_id
    delete logout_path
    sign_in_as(@user_a)
    get analytics_path(survey_id: @survey_b.id, customer_id: @customer_b.id)
    assert_response :success

    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">3</div>"
    refute_includes response.body, "Beta Feedback Survey"
  end

  # =========================================================================
  # 8. Live Public Submission End-to-End Test
  # =========================================================================

  test "live public submission updates daily metrics and analytics page" do
    today = Date.current

    # Verify baseline count for Customer A
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success
    assert_includes response.body, "No response data in the last 90 days"

    delete logout_path

    # Unauthenticated respondent visits public survey URL
    get public_survey_path(@survey_a1.public_token)
    assert_response :success

    # Respondent submits survey answers
    assert_difference -> { @survey_a1.submissions.count }, 1 do
      perform_enqueued_jobs do
        post submit_public_survey_path(@survey_a1.public_token), params: {
          answers: {
            @q_a1.id.to_s => @opt_a1.id
          }
        }
      end
    end
    assert_redirected_to public_survey_success_path(@survey_a1.public_token)

    # Daily metric must be updated
    metric = SurveyDailyMetric.find_by(survey: @survey_a1, date: today)
    assert_not_nil metric
    assert_equal 1, metric.response_count

    # Owner logs back in and checks analytics
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">1</div>"
    assert_includes response.body, today.strftime("%Y-%m-%d")
    assert_includes response.body, "Alpha CSAT Survey"
  end

  # =========================================================================
  # 9. Empty Analytics State Tests
  # =========================================================================

  test "empty state renders cleanly when customer has no responses" do
    empty_customer = Customer.create!(name: "Gamma Holdings")
    empty_user = empty_customer.users.create!(
      name: "Grace Gamma",
      email: "grace@gamma.test",
      password: "ChangeMe123!"
    )

    sign_in_as(empty_user)
    get analytics_path
    assert_response :success

    assert_includes response.body, "Gamma Holdings Analytics"
    assert_includes response.body, "No response data in the last 90 days"
    assert_includes response.body, "Once respondents complete your customer surveys, daily response analytics will be automatically calculated here."
    assert_includes response.body, "View Surveys"
  end

  # =========================================================================
  # 10. Time Zone Boundary Testing
  # =========================================================================

  test "submissions at midnight boundaries are bucketed to correct dates" do
    d1 = Date.new(2026, 7, 1)
    d2 = Date.new(2026, 7, 2)

    t1 = Time.zone.parse("2026-07-01 23:59:59")
    t2 = Time.zone.parse("2026-07-02 00:00:01")

    perform_enqueued_jobs do
      @survey_a1.submissions.create!(submitted_at: t1)
      @survey_a1.submissions.create!(submitted_at: t2)
    end

    m1 = SurveyDailyMetric.find_by(survey: @survey_a1, date: d1)
    m2 = SurveyDailyMetric.find_by(survey: @survey_a1, date: d2)

    assert_not_nil m1, "Metric for 2026-07-01 must exist"
    assert_not_nil m2, "Metric for 2026-07-02 must exist"
    assert_equal 1, m1.response_count
    assert_equal 1, m2.response_count
  end

  # =========================================================================
  # 11. Backfill Rake Task Idempotency & Accuracy
  # =========================================================================

  test "analytics:backfill task reconstructs metrics accurately and idempotently" do
    SurveyDailyMetric.delete_all

    # Seed 6 submissions across 2 dates for survey A1, 2 for survey B
    d1 = 10.days.ago.to_date
    d2 = 5.days.ago.to_date

    4.times { Submission.insert!({ survey_id: @survey_a1.id, submitted_at: 10.days.ago, created_at: Time.current, updated_at: Time.current }) }
    2.times { Submission.insert!({ survey_id: @survey_a1.id, submitted_at: 5.days.ago, created_at: Time.current, updated_at: Time.current }) }
    2.times { Submission.insert!({ survey_id: @survey_b.id, submitted_at: 5.days.ago, created_at: Time.current, updated_at: Time.current }) }

    assert_equal 0, SurveyDailyMetric.count

    # First run of backfill
    Rake::Task["analytics:backfill"].reenable
    Rake::Task["analytics:backfill"].invoke

    assert_equal 3, SurveyDailyMetric.count
    assert_equal 4, SurveyDailyMetric.find_by(survey: @survey_a1, date: d1).response_count
    assert_equal 2, SurveyDailyMetric.find_by(survey: @survey_a1, date: d2).response_count
    assert_equal 2, SurveyDailyMetric.find_by(survey: @survey_b, date: d2).response_count

    # Second run of backfill (Idempotency test)
    Rake::Task["analytics:backfill"].reenable
    Rake::Task["analytics:backfill"].invoke

    assert_equal 3, SurveyDailyMetric.count
    assert_equal 4, SurveyDailyMetric.find_by(survey: @survey_a1, date: d1).response_count
  end
end
