# frozen_string_literal: true

require "test_helper"

class AnalyticsDateRangeFilterTest < ActionDispatch::IntegrationTest
  setup do
    # Customer A
    @customer_a = Customer.create!(name: "Alpha Filter Corp")
    @user_a = @customer_a.users.create!(
      name: "Alice Alpha",
      email: "alice_filter@alphacorp.test",
      password: "ChangeMe123!"
    )
    @survey_a = @customer_a.surveys.create!(
      title: "Alpha Main Survey",
      status: :published,
      published_at: 1.year.ago
    )

    # Customer B (for Tenant Isolation testing)
    @customer_b = Customer.create!(name: "Beta Filter Corp")
    @user_b = @customer_b.users.create!(
      name: "Bob Beta",
      email: "bob_filter@betacorp.test",
      password: "ChangeMe123!"
    )
    @survey_b = @customer_b.surveys.create!(
      title: "Beta Main Survey",
      status: :published,
      published_at: 1.year.ago
    )

    # Setup controlled historical submissions for Customer A
    # Today is in 2026
    perform_enqueued_jobs do
      # 10 days ago (within 30d, 90d, YTD, All)
      2.times { @survey_a.submissions.create!(submitted_at: 10.days.ago) }

      # 45 days ago (outside 30d, within 90d, YTD, All)
      3.times { @survey_a.submissions.create!(submitted_at: 45.days.ago) }

      # 100 days ago (outside 30d, outside 90d; within YTD if current month >= April, within All)
      4.times { @survey_a.submissions.create!(submitted_at: 100.days.ago) }

      # 400 days ago (outside 30d, 90d, YTD; within All)
      5.times { @survey_a.submissions.create!(submitted_at: 400.days.ago) }

      # Customer B submissions on overlapping dates
      10.times { @survey_b.submissions.create!(submitted_at: 10.days.ago) }
      20.times { @survey_b.submissions.create!(submitted_at: 45.days.ago) }
      30.times { @survey_b.submissions.create!(submitted_at: 400.days.ago) }
    end
  end

  # =========================================================================
  # 1. Default Behavior
  # =========================================================================

  test "default analytics window is 90 days when no parameters are passed" do
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success

    # Header and stats show 90-day window
    assert_includes response.body, "over the last 90 days"
    assert_includes response.body, "Total 90-Day Responses"
    assert_select "a#filter-range-90d.btn-primary"

    # Count includes 10-day (2) and 45-day (3) = 5 total. 100-day and 400-day are excluded.
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
  end

  test "explicit range=90d produces identical output to default" do
    sign_in_as(@user_a)
    get analytics_path(range: "90d")
    assert_response :success

    assert_includes response.body, "over the last 90 days"
    assert_includes response.body, "Total 90-Day Responses"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
  end

  # =========================================================================
  # 2. Preset: Last 30 Days (range=30d)
  # =========================================================================

  test "range=30d strictly filters to responses within the past 30 days" do
    sign_in_as(@user_a)
    get analytics_path(range: "30d")
    assert_response :success

    assert_includes response.body, "over the last 30 days"
    assert_includes response.body, "Total 30-Day Responses"
    assert_select "a#filter-range-30d.btn-primary"

    # Only 10-day responses (2) should be counted. 45-day, 100-day, and 400-day are excluded.
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">2</div>"
    assert_includes response.body, 10.days.ago.to_date.strftime("%Y-%m-%d")
    refute_includes response.body, 45.days.ago.to_date.strftime("%Y-%m-%d")
  end

  # =========================================================================
  # 3. Preset: Year to Date (range=ytd)
  # =========================================================================

  test "range=ytd filters to responses from beginning of current year" do
    sign_in_as(@user_a)
    get analytics_path(range: "ytd")
    assert_response :success

    assert_includes response.body, "for year to date"
    assert_includes response.body, "Total YTD Responses"
    assert_select "a#filter-range-ytd.btn-primary"

    # 400-day responses (from previous year) must be excluded
    d_400 = 400.days.ago.to_date
    refute_includes response.body, d_400.strftime("%Y-%m-%d")

    # Current year submissions (10d, 45d, 100d if in current year) are included
    expected_ytd = @customer_a.survey_daily_metrics
                              .where("date >= ?", Date.current.beginning_of_year)
                              .sum(:response_count)
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">#{expected_ytd}</div>"
  end

  # =========================================================================
  # 4. Preset: All Time (range=all)
  # =========================================================================

  test "range=all includes all historical responses for current customer" do
    sign_in_as(@user_a)
    get analytics_path(range: "all")
    assert_response :success

    assert_includes response.body, "across all time"
    assert_includes response.body, "Total All-Time Responses"
    assert_select "a#filter-range-all.btn-primary"

    # All Customer A submissions: 2 (10d) + 3 (45d) + 4 (100d) + 5 (400d) = 14
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">14</div>"
    assert_includes response.body, 10.days.ago.to_date.strftime("%Y-%m-%d")
    assert_includes response.body, 45.days.ago.to_date.strftime("%Y-%m-%d")
    assert_includes response.body, 100.days.ago.to_date.strftime("%Y-%m-%d")
    assert_includes response.body, 400.days.ago.to_date.strftime("%Y-%m-%d")
  end

  # =========================================================================
  # 5. Custom Range (start_date & end_date)
  # =========================================================================

  test "custom start_date and end_date filters correctly and inclusively" do
    # Target window covering 45-day submissions only
    s_date = 50.days.ago.to_date
    e_date = 40.days.ago.to_date

    sign_in_as(@user_a)
    get analytics_path(start_date: s_date.to_s, end_date: e_date.to_s)
    assert_response :success

    assert_includes response.body, "Total Period Responses"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">3</div>"
    assert_includes response.body, 45.days.ago.to_date.strftime("%Y-%m-%d")
    refute_includes response.body, 10.days.ago.to_date.strftime("%Y-%m-%d")
  end

  # =========================================================================
  # 6. Invalid & Malicious Parameters Handling
  # =========================================================================

  test "unsupported or malicious range preset safely defaults to 90 days" do
    sign_in_as(@user_a)

    [ "banana", "999999", "<script>alert(1)</script>", "../../etc/passwd", "drop table surveys;" ].each do |bad_preset|
      get analytics_path(range: bad_preset)
      assert_response :success
      assert_includes response.body, "Total 90-Day Responses"
      assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
    end
  end

  test "custom range with start_date after end_date falls back safely to default" do
    sign_in_as(@user_a)
    get analytics_path(start_date: "2026-10-20", end_date: "2026-10-10")
    assert_response :success

    assert_includes response.body, "Start date must be on or before end date. Showing default 90 days."
    assert_includes response.body, "Total 90-Day Responses"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
  end

  test "custom range with invalid date format falls back safely to default" do
    sign_in_as(@user_a)
    get analytics_path(start_date: "invalid-date", end_date: "2026-10-27")
    assert_response :success

    assert_includes response.body, "Invalid date format provided. Showing default 90 days."
    assert_includes response.body, "Total 90-Day Responses"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
  end

  test "custom range with missing end_date falls back safely to default" do
    sign_in_as(@user_a)
    get analytics_path(start_date: "2026-10-01", end_date: "")
    assert_response :success

    assert_includes response.body, "Both start date and end date are required for a custom range. Showing default 90 days."
    assert_includes response.body, "Total 90-Day Responses"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">5</div>"
  end

  test "custom range for future dates displays safe empty state" do
    sign_in_as(@user_a)
    get analytics_path(start_date: "2050-01-01", end_date: "2050-01-31")
    assert_response :success

    assert_includes response.body, "No response data for the selected date range"
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">0</div>"
  end

  # =========================================================================
  # 7. Authentication Protection on All Date Filter Routes
  # =========================================================================

  test "unauthenticated requests with range parameters are redirected to login" do
    [
      analytics_path(range: "30d"),
      analytics_path(range: "90d"),
      analytics_path(range: "ytd"),
      analytics_path(range: "all"),
      analytics_path(start_date: "2026-01-01", end_date: "2026-06-01")
    ].each do |path|
      get path
      assert_redirected_to login_path
    end
  end

  # =========================================================================
  # 8. Strict Multi-Tenant Isolation
  # =========================================================================

  test "tenant isolation is strictly maintained across all date filters" do
    sign_in_as(@user_a)

    # 30-day filter
    get analytics_path(range: "30d")
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">2</div>"
    refute_includes response.body, "Beta Filter Corp"
    refute_includes response.body, ">10</span>"

    # All-time filter
    get analytics_path(range: "all")
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">14</div>"
    refute_includes response.body, ">60</span>" # Customer B total (10+20+30)

    # Log in as Customer B
    delete logout_path
    sign_in_as(@user_b)

    # Customer B 30-day view
    get analytics_path(range: "30d")
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">10</div>"
    refute_includes response.body, "Alpha Filter Corp"

    # Customer B all-time view
    get analytics_path(range: "all")
    assert_includes response.body, "<div class=\"stat-value\" style=\"color: var(--primary);\">60</div>"
    refute_includes response.body, "Alpha Filter Corp"
  end
end
