# frozen_string_literal: true

require "application_system_test_case"

class AnalyticsFilterSystemTest < ApplicationSystemTestCase
  setup do
    @customer = Customer.create!(name: "System Analytics Corp")
    @user = @customer.users.create!(
      name: "Sam System",
      email: "sam_system@analytics.test",
      password: "ChangeMe123!"
    )

    @survey = @customer.surveys.create!(
      title: "Quarterly Evaluation Survey",
      status: :published,
      published_at: 1.year.ago
    )

    # Historical submissions across different ranges
    perform_enqueued_jobs do
      # 10 days ago (within 30d, 90d, YTD, All)
      2.times { @survey.submissions.create!(submitted_at: 10.days.ago) }

      # 45 days ago (outside 30d, within 90d, YTD, All)
      3.times { @survey.submissions.create!(submitted_at: 45.days.ago) }

      # 400 days ago (outside 30d, 90d, YTD; within All)
      4.times { @survey.submissions.create!(submitted_at: 400.days.ago) }
    end
  end

  test "real browser interactive date filter switching between presets and custom range" do
    sign_in_as(@user)

    # 1. Visit Analytics page
    visit analytics_path

    # Verify default = Last 90 days
    assert_text(/Total 90-Day Responses/i)
    assert_text "5" # 2 (10d) + 3 (45d)
    assert_selector "#filter-range-90d.btn-primary"

    # 2. Click "Last 30 days" preset
    click_link "Last 30 days"
    assert_current_path analytics_path(range: "30d")
    assert_text(/Total 30-Day Responses/i)
    assert_text "2" # only 10d
    assert_selector "#filter-range-30d.btn-primary"
    assert_selector "#filter-range-90d.btn-secondary"

    # 3. Click "Year to date" preset
    click_link "Year to date"
    assert_current_path analytics_path(range: "ytd")
    assert_text(/Total YTD Responses/i)
    assert_selector "#filter-range-ytd.btn-primary"

    # 4. Click "All time" preset
    click_link "All time"
    assert_current_path analytics_path(range: "all")
    assert_text(/Total All-Time Responses/i)
    assert_text "9" # 2 + 3 + 4 = 9 total
    assert_selector "#filter-range-all.btn-primary"

    # 5. Apply custom date range
    s_date = 50.days.ago.to_date.iso8601
    e_date = 40.days.ago.to_date.iso8601

    page.execute_script("document.getElementById('start_date').value = arguments[0]; document.getElementById('end_date').value = arguments[1];", s_date, e_date)
    click_button "Apply"

    assert_text(/Total Period Responses/i)
    assert_text "3" # only the 45-day submissions
    assert_text 45.days.ago.to_date.strftime("%Y-%m-%d")

    # 6. Click Reset link
    click_link "Reset"
    assert_current_path analytics_path
    assert_text(/Total 90-Day Responses/i)
  end
end
