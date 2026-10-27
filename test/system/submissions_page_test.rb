# frozen_string_literal: true

require "application_system_test_case"

class SubmissionsPageTest < ApplicationSystemTestCase
  setup do
    @customer = Customer.create!(name: "Acme Global")
    @user = @customer.users.create!(
      name: "Admin User",
      email: "sys_admin@acme.test",
      password: "ChangeMe123!"
    )

    @survey = @customer.surveys.create!(
      title: "System Test Customer Survey",
      description: "Real browser end-to-end customer feedback",
      status: :published,
      published_at: Time.current
    )

    @q_text = @survey.questions.create!(question_text: "What is your full name?", question_type: :text, position: 1, required: true)
    @q_num = @survey.questions.create!(question_text: "Rate your satisfaction (1-10)?", question_type: :number, position: 2, required: true)
    @q_mc = @survey.questions.create!(question_text: "Primary cloud provider?", question_type: :multiple_choice, position: 3, required: true)
    @opt_aws = @q_mc.question_options.create!(label: "Amazon Web Services", position: 1)
    @opt_gcp = @q_mc.question_options.create!(label: "Google Cloud Platform", position: 2)
    @opt_azure = @q_mc.question_options.create!(label: "Microsoft Azure", position: 3)
    @q_opt = @survey.questions.create!(question_text: "Any additional feedback?", question_type: :text, position: 4, required: false)

    # Sub 1: Complete submission
    @sub1 = @survey.submissions.create!(submitted_at: 2.hours.ago)
    @sub1.answers.create!(question: @q_text, text_value: "Alice Browser")
    @sub1.answers.create!(question: @q_num, number_value: 9)
    @sub1.answers.create!(question: @q_mc, selected_option: @opt_gcp)
    @sub1.answers.create!(question: @q_opt, text_value: "The UI is blazing fast!")

    # Sub 2: Unanswered optional question
    @sub2 = @survey.submissions.create!(submitted_at: 1.hour.ago)
    @sub2.answers.create!(question: @q_text, text_value: "Bob Browser")
    @sub2.answers.create!(question: @q_num, number_value: 8)
    @sub2.answers.create!(question: @q_mc, selected_option: @opt_aws)

    # Sub 3: XSS payload in text
    @sub3 = @survey.submissions.create!(submitted_at: 30.minutes.ago)
    @sub3.answers.create!(question: @q_text, text_value: "<script>alert('XSS_BROWSER')</script>")
    @sub3.answers.create!(question: @q_num, number_value: 5)
    @sub3.answers.create!(question: @q_mc, selected_option: @opt_azure)
  end

  test "real browser login and submission list navigation" do
    # 1. Start unauthenticated and visit submissions page
    visit survey_submissions_path(@survey)
    assert_current_path login_path
    assert_text "You must log in to access this page."

    # 2. Complete browser login flow
    fill_in "Email Address", with: @user.email
    fill_in "Password", with: "ChangeMe123!"
    click_button "Log in"

    # Lands on dashboard
    assert_current_path dashboard_path
    assert_text "Welcome back, Admin User!"

    # 3. Navigate to Survey Submissions
    visit survey_submissions_path(@survey)
    assert_current_path survey_submissions_path(@survey)

    # DOM-visible assertions
    assert_selector "h1", text: "Survey Responses"
    assert_text "Submissions for: System Test Customer Survey"
    assert_text "Showing 1–3 of 3 submissions"
    assert_text "##{@sub3.id}"
    assert_text "##{@sub2.id}"
    assert_text "##{@sub1.id}"
  end

  test "real browser submission details view with text number and option label" do
    sign_in_as(@user)

    # Visit submissions index and click into Submission 1
    visit survey_submissions_path(@survey)
    row = find("tr", text: "##{@sub1.id}")
    within(row) do
      click_link "View Details →"
    end

    # Confirm detail page loads in browser
    assert_current_path survey_submission_path(@survey, @sub1)
    assert_selector "h1", text: "Submission Details"
    assert_text "System Test Customer Survey"
    assert_text "Submission ID: ##{@sub1.id}"

    # Verify answers rendered in browser DOM
    assert_text "What is your full name?"
    assert_text "Alice Browser"

    assert_text "Rate your satisfaction (1-10)?"
    assert_text "9"

    assert_text "Primary cloud provider?"
    assert_text "Google Cloud Platform" # Resolved label, NOT option ID

    assert_text "Any additional feedback?"
    assert_text "The UI is blazing fast!"
  end

  test "real browser optional unanswered question displays graceful placeholder" do
    sign_in_as(@user)

    # Visit Sub 2 (optional question was omitted)
    visit survey_submission_path(@survey, @sub2)
    assert_selector "h1", text: "Submission Details"

    # Verify question is listed and renders placeholder rather than nil or crashing
    assert_text "Any additional feedback?"
    assert_text "No response provided"
    assert_no_text "nil"
  end

  test "real browser XSS safety prevents script execution and renders escaped text" do
    sign_in_as(@user)

    # Visit Sub 3 (contains <script> tag)
    visit survey_submission_path(@survey, @sub3)
    assert_selector "h1", text: "Submission Details"

    # The payload must be rendered as visible text, NOT executed
    assert_text "<script>alert('XSS_BROWSER')</script>"
  end

  test "real browser pagination navigation through next and previous pages" do
    # Create 22 more submissions (total = 25 submissions across 2 pages)
    22.times do |i|
      sub = @survey.submissions.create!(submitted_at: (3 + i).hours.ago)
      sub.answers.create!(question: @q_text, text_value: "Batch Respondent #{i}")
    end

    sign_in_as(@user)

    # Visit submissions list
    visit survey_submissions_path(@survey)

    # Page 1 checks
    assert_text "Showing 1–20 of 25 submissions"
    assert_text "Page 1 of 2"
    assert_selector ".pagination-next"

    # Click Next
    find(".pagination-next").click

    # Page 2 checks
    assert_text "Showing 21–25 of 25 submissions"
    assert_text "Page 2 of 2"
    assert_selector ".pagination-prev"

    # Click Previous to return to Page 1
    find(".pagination-prev").click
    assert_text "Showing 1–20 of 25 submissions"
    assert_text "Page 1 of 2"
  end
end
