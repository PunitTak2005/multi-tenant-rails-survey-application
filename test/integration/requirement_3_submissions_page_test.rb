# frozen_string_literal: true

require "test_helper"

class Requirement3SubmissionsPageTest < ActionDispatch::IntegrationTest
  setup do
    # Customer A
    @customer_a = Customer.create!(name: "Alpha Corp")
    @user_a = @customer_a.users.create!(
      name: "Alice Alpha",
      email: "user_a@example.com",
      password: "ChangeMe123!"
    )

    # Survey A1: Multi-question survey (Text, Number, Multiple Choice, Optional Text)
    @survey_a1 = @customer_a.surveys.create!(
      title: "Survey A1 - Product Feedback",
      description: "Customer A customer satisfaction survey",
      status: :published,
      published_at: Time.current
    )
    @q_text = @survey_a1.questions.create!(
      question_text: "What is your name?",
      question_type: :text,
      position: 1,
      required: true
    )
    @q_num = @survey_a1.questions.create!(
      question_text: "What is your age?",
      question_type: :number,
      position: 2,
      required: true
    )
    @q_mc = @survey_a1.questions.create!(
      question_text: "What is your favorite color?",
      question_type: :multiple_choice,
      position: 3,
      required: true
    )
    @opt_red = @q_mc.question_options.create!(label: "Red", position: 1)
    @opt_blue = @q_mc.question_options.create!(label: "Blue", position: 2)
    @opt_green = @q_mc.question_options.create!(label: "Green", position: 3)

    @q_opt = @survey_a1.questions.create!(
      question_text: "Additional comments?",
      question_type: :text,
      position: 4,
      required: false
    )

    # Submissions for Survey A1
    # Submission A1-1: Complete answers
    @sub_a1_1 = @survey_a1.submissions.create!(submitted_at: 3.hours.ago)
    @sub_a1_1.answers.create!(question: @q_text, text_value: "Alice")
    @sub_a1_1.answers.create!(question: @q_num, number_value: 21)
    @sub_a1_1.answers.create!(question: @q_mc, selected_option: @opt_red)
    @sub_a1_1.answers.create!(question: @q_opt, text_value: "Great product and fast support!")

    # Submission A1-2: Optional Q4 omitted
    @sub_a1_2 = @survey_a1.submissions.create!(submitted_at: 2.hours.ago)
    @sub_a1_2.answers.create!(question: @q_text, text_value: "Bob")
    @sub_a1_2.answers.create!(question: @q_num, number_value: 27)
    @sub_a1_2.answers.create!(question: @q_mc, selected_option: @opt_blue)

    # Submission A1-3: XSS payload in text
    @sub_a1_3 = @survey_a1.submissions.create!(submitted_at: 1.hour.ago)
    @sub_a1_3.answers.create!(question: @q_text, text_value: "<script>alert('XSS')</script>")
    @sub_a1_3.answers.create!(question: @q_num, number_value: 31)
    @sub_a1_3.answers.create!(question: @q_mc, selected_option: @opt_green)
    @sub_a1_3.answers.create!(question: @q_opt, text_value: "<script>alert('XSS')</script>")

    # Survey A2: Internal Survey
    @survey_a2 = @customer_a.surveys.create!(
      title: "Survey A2 - Internal Ops",
      description: "Internal operations",
      status: :published,
      published_at: Time.current
    )
    @q_a2 = @survey_a2.questions.create!(
      question_text: "Internal notes",
      question_type: :text,
      position: 1,
      required: true
    )
    @sub_a2_1 = @survey_a2.submissions.create!(submitted_at: 30.minutes.ago)
    @sub_a2_1.answers.create!(question: @q_a2, text_value: "Confidential internal ops")

    # Survey A3: Empty State (0 submissions)
    @survey_a3 = @customer_a.surveys.create!(
      title: "Survey A3 - Empty State",
      description: "No submissions yet",
      status: :published,
      published_at: Time.current
    )
    @survey_a3.questions.create!(
      question_text: "Future ideas",
      question_type: :text,
      position: 1,
      required: false
    )

    # Customer B
    @customer_b = Customer.create!(name: "Beta Industries")
    @user_b = @customer_b.users.create!(
      name: "Bob Beta",
      email: "user_b@example.com",
      password: "ChangeMe123!"
    )
    @survey_b1 = @customer_b.surveys.create!(
      title: "Survey B1 - Market Analysis",
      description: "Customer B confidential survey",
      status: :published,
      published_at: Time.current
    )
    @q_b1 = @survey_b1.questions.create!(
      question_text: "Competitor intel",
      question_type: :text,
      position: 1,
      required: true
    )
    @sub_b1_1 = @survey_b1.submissions.create!(submitted_at: 10.minutes.ago)
    @sub_b1_1.answers.create!(question: @q_b1, text_value: "Customer B confidential data")
  end

  # =========================================================================
  # 1. Authentication Tests (Section 6)
  # =========================================================================

  test "unauthenticated request to submissions index redirects to login" do
    get survey_submissions_path(@survey_a1)
    assert_redirected_to login_path
    follow_redirect!
    assert_includes flash[:alert], "You must log in to access this page."
  end

  test "unauthenticated request to submission details redirects to login" do
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_redirected_to login_path
    follow_redirect!
    assert_includes flash[:alert], "You must log in to access this page."
  end

  test "unauthenticated requests do not leak any submission data or answers" do
    get survey_submissions_path(@survey_a1)
    assert_not_includes response.body, "Alice"
    assert_not_includes response.body, "Bob"
    assert_not_includes response.body, "Charlie"

    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_not_includes response.body, "Alice"
    assert_not_includes response.body, "Great product"
  end

  # =========================================================================
  # 2. Authenticated Submissions List Tests (Sections 7, 8, 9)
  # =========================================================================

  test "authenticated Customer A can access submissions index and view all submissions" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1)

    assert_response :success
    assert_includes response.body, "Survey Responses"
    assert_includes response.body, "Submissions for: <strong>Survey A1 - Product Feedback</strong> (3 total)"

    # Verify all 3 submission IDs appear
    assert_includes response.body, "##{@sub_a1_1.id}"
    assert_includes response.body, "##{@sub_a1_1.id}"
    assert_includes response.body, "##{@sub_a1_3.id}"
  end

  test "submissions index displays accurate metadata: ID, timestamp, and answer counts" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1)
    assert_response :success

    # Verified against database records
    assert_equal 3, @survey_a1.submissions.count
    assert_includes response.body, "##{@sub_a1_1.id}"
    assert_includes response.body, @sub_a1_1.submitted_at.strftime("%b %d, %Y")
    assert_includes response.body, "#{@sub_a1_1.answers.count} answers"
    assert_includes response.body, "#{@sub_a1_2.answers.count} answers"

    # Navigation links present
    assert_includes response.body, "View Details &rarr;"
    assert_includes response.body, "Open Public Survey"
  end

  test "submissions index displays sample preview with safe formatting" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1)
    assert_response :success

    # Sample preview shows question text and answer value
    assert_includes response.body, "What is your name?"
    assert_includes response.body, "Alice"
    assert_includes response.body, "Bob"
    assert_includes response.body, "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
  end

  # =========================================================================
  # 3. Empty State Test (Section 10)
  # =========================================================================

  test "submissions index handles empty state when survey has zero responses" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a3)
    assert_response :success

    assert_includes response.body, "No responses yet"
    assert_includes response.body, "This survey has not received any submissions yet."
    assert_includes response.body, "Share your public survey link to collect responses:"
    assert_includes response.body, public_survey_url(@survey_a3.public_token)
    assert_not_includes response.body, "<tbody>"
  end

  # =========================================================================
  # 4. Submission Details: Answer Types & Questions (Sections 11-16)
  # =========================================================================

  test "authenticated Customer A can open submission details and view text answer" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_response :success

    assert_includes response.body, "Submission Details"
    assert_includes response.body, "Survey A1 - Product Feedback"
    assert_includes response.body, "Submission ID: ##{@sub_a1_1.id}"
    assert_includes response.body, "What is your name?"
    assert_includes response.body, "Alice"
  end

  test "authenticated Customer A can open submission details and view number answer" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_response :success

    assert_includes response.body, "What is your age?"
    assert_includes response.body, "21"
  end

  test "authenticated Customer A can open submission details and view multiple choice option label" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_response :success

    assert_includes response.body, "What is your favorite color?"
    assert_includes response.body, "Red"
    assert_not_includes response.body, "option_id"
  end

  test "submission details gracefully handles unanswered optional question without crashing or nil" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_2)
    assert_response :success

    # Verified: Q4 is optional and was not answered in Sub A1-2
    assert_includes response.body, "Additional comments?"
    assert_includes response.body, "No response provided"
    assert_not_includes response.body, "nil"
  end

  test "submission details clearly marks required questions" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_response :success

    assert_includes response.body, "REQUIRED"
  end

  test "multiple submissions are displayed and answers do not leak between submissions" do
    sign_in_as(@user_a)

    # Submission 1 details
    get survey_submission_path(@survey_a1, @sub_a1_1)
    assert_response :success
    assert_includes response.body, "Alice"
    assert_includes response.body, "Red"
    assert_not_includes response.body, "Bob"
    assert_not_includes response.body, "Blue"
    assert_not_includes response.body, "Green"

    # Submission 2 details
    get survey_submission_path(@survey_a1, @sub_a1_2)
    assert_response :success
    assert_includes response.body, "Bob"
    assert_includes response.body, "Blue"
    assert_not_includes response.body, "Alice"
    assert_not_includes response.body, "Red"
    assert_not_includes response.body, "Green"

    # Submission 3 details
    get survey_submission_path(@survey_a1, @sub_a1_3)
    assert_response :success
    assert_includes response.body, "Green"
    assert_includes response.body, "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
    assert_not_includes response.body, "Alice"
    assert_not_includes response.body, "Bob"
  end

  # =========================================================================
  # 5. Critical Tenant Isolation Tests (Sections 19, 21, 22)
  # =========================================================================

  test "critical tenant isolation: Customer A cannot view Customer B's submissions index" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_b1)

    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
    assert_not_includes response.body, "Survey B1 - Market Analysis"
  end

  test "critical tenant isolation: Customer A cannot view Customer B's submission details" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_b1, @sub_b1_1)

    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
    assert_not_includes response.body, "Customer B confidential data"
  end

  test "critical tenant isolation: Customer B cannot view Customer A's submissions index" do
    sign_in_as(@user_b)
    get survey_submissions_path(@survey_a1)

    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
    assert_not_includes response.body, "Survey A1 - Product Feedback"
  end

  test "critical tenant isolation: Customer B cannot view Customer A's submission details" do
    sign_in_as(@user_b)
    get survey_submission_path(@survey_a1, @sub_a1_1)

    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
    assert_not_includes response.body, "Alice"
    assert_not_includes response.body, "Great product"
  end

  # =========================================================================
  # 6. Critical IDOR & Cross-Survey Isolation Tests (Sections 19, 20)
  # =========================================================================

  test "cross-survey IDOR: Customer A cannot view Survey A2 submission via Survey A1 route" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a2_1)

    # Scoped find raises ActiveRecord::RecordNotFound -> redirected to Survey A1 submissions
    assert_redirected_to survey_submissions_path(@survey_a1)
    follow_redirect!
    assert_includes flash[:alert], "Submission not found."
    assert_not_includes response.body, "Confidential internal ops"
  end

  test "cross-survey IDOR: Customer A cannot view Survey A1 submission via Survey A2 route" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a2, @sub_a1_1)

    assert_redirected_to survey_submissions_path(@survey_a2)
    follow_redirect!
    assert_includes flash[:alert], "Submission not found."
    assert_not_includes response.body, "Alice"
  end

  test "non-existent submission ID returns safe redirect with alert" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, id: 999_999_999)

    assert_redirected_to survey_submissions_path(@survey_a1)
    follow_redirect!
    assert_includes flash[:alert], "Submission not found."
  end

  # =========================================================================
  # 7. Parameter Tampering & Mass Assignment (Sections 23, 24)
  # =========================================================================

  test "parameter tampering: tampering customer_id in query parameters is ignored" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1, customer_id: @customer_b.id)
    assert_response :success

    # Confirms query remained scoped to Customer A
    assert_includes response.body, "Survey A1 - Product Feedback"
    assert_not_includes response.body, "Survey B1 - Market Analysis"
  end

  test "parameter tampering: tampering survey_id in query parameters is ignored or safely blocked" do
    sign_in_as(@user_a)

    # 1. Tampering with extra query params does not affect authorized survey display
    get survey_submission_path(@survey_a1, @sub_a1_1, tampered_survey_id: @survey_b1.id)
    assert_response :success
    assert_includes response.body, "Alice"

    # 2. Attempting to override the route's survey_id with Customer B's survey is blocked
    get survey_submission_path(survey_id: @survey_b1.id, id: @sub_a1_1.id)
    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
  end

  # =========================================================================
  # 8. XSS & Output Encoding Tests (Section 30)
  # =========================================================================

  test "XSS output encoding: malicious script payloads in text answers are safely escaped in list view" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1)
    assert_response :success

    # Must NOT render unescaped <script> tag
    assert_not_includes response.body, "<script>alert('XSS')</script>"
    # Must be escaped HTML entities
    assert_includes response.body, "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
  end

  test "XSS output encoding: malicious script payloads in text answers are safely escaped in detail view" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_a1, @sub_a1_3)
    assert_response :success

    # Must NOT render unescaped <script> tag
    assert_not_includes response.body, "<script>alert('XSS')</script>"
    assert_includes response.body, "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
  end

  # =========================================================================
  # 9. Performance & Query Count Verification (Sections 26, 27, 28)
  # =========================================================================

  test "submissions index avoids N+1 queries by eager loading associations" do
    sign_in_as(@user_a)

    # Measure initial query count with 3 submissions
    initial_queries = 0
    callback = ->(*, payload) { initial_queries += 1 unless payload[:name] =~ /SCHEMA|TRANSACTION/ }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get survey_submissions_path(@survey_a1)
    end
    assert_response :success

    # Create 3 more submissions to double the volume
    3.times do |i|
      sub = @survey_a1.submissions.create!(submitted_at: (4 + i).hours.ago)
      sub.answers.create!(question: @q_text, text_value: "Respondent #{i}")
      sub.answers.create!(question: @q_num, number_value: 20 + i)
      sub.answers.create!(question: @q_mc, selected_option: @opt_red)
    end

    # Measure query count with 6 submissions (double dataset)
    subsequent_queries = 0
    callback_subsequent = ->(*, payload) { subsequent_queries += 1 unless payload[:name] =~ /SCHEMA|TRANSACTION/ }

    ActiveSupport::Notifications.subscribed(callback_subsequent, "sql.active_record") do
      get survey_submissions_path(@survey_a1)
    end
    assert_response :success

    # Query count must remain completely constant (zero N+1 queries)
    assert_equal initial_queries, subsequent_queries, "Query count increased from #{initial_queries} to #{subsequent_queries}, indicating an N+1 query!"
    assert_operator subsequent_queries, :<=, 10
  end

  test "submissions are strictly ordered newest first by submitted_at" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_a1)
    assert_response :success

    pos_3 = response.body.index("##{@sub_a1_3.id}")
    pos_2 = response.body.index("##{@sub_a1_2.id}")
    pos_1 = response.body.index("##{@sub_a1_1.id}")

    # Sub A1-3 was submitted 1 hour ago (newest)
    # Sub A1-2 was submitted 2 hours ago
    # Sub A1-1 was submitted 3 hours ago (oldest)
    assert pos_3 < pos_2, "Expected newest submission (Sub 3) before Sub 2"
    assert pos_2 < pos_1, "Expected Sub 2 before oldest submission (Sub 1)"
  end

  # =========================================================================
  # 10. Analytics Compatibility (Section 33)
  # =========================================================================

  test "submissions update analytics correctly and do not break analytics dashboard" do
    sign_in_as(@user_a)

    get analytics_path
    assert_response :success
    assert_includes response.body, "Alpha Corp Analytics"
    assert_includes response.body, "Survey A1 - Product Feedback"
    assert_not_includes response.body, "Survey B1 - Market Analysis"
  end

  # =========================================================================
  # 11. Dedicated Pagination Tests (Part 1, Sections 1-12)
  # =========================================================================

  test "pagination limits results to default page size (20) and shows navigation controls" do
    sign_in_as(@user_a)

    # Add 25 submissions to Survey A1 (total = 28 submissions)
    25.times do |i|
      sub = @survey_a1.submissions.create!(submitted_at: (5 + i).hours.ago)
      sub.answers.create!(question: @q_text, text_value: "Bulk #{i}")
    end

    get survey_submissions_path(@survey_a1, page: 1)
    assert_response :success

    # Page 1 contains exactly 20 rows
    assert_includes response.body, "Showing <strong>1&ndash;20</strong> of <strong>28</strong> submissions"
    assert_includes response.body, "Page <strong>1</strong> of <strong>2</strong>"
    assert_includes response.body, "Next &rarr;"
    assert_includes response.body, "pagination-prev-disabled"
  end

  test "pagination page navigation loads distinct disjoint subsets across pages" do
    sign_in_as(@user_a)

    # Ensure 25 submissions
    created_ids = []
    25.times do |i|
      sub = @survey_a1.submissions.create!(submitted_at: (10 + i).minutes.ago)
      sub.answers.create!(question: @q_text, text_value: "Batch #{i}")
      created_ids << sub.id
    end

    # Fetch Page 1
    get survey_submissions_path(@survey_a1, page: 1)
    assert_response :success
    page1_html = response.body

    # Fetch Page 2
    get survey_submissions_path(@survey_a1, page: 2)
    assert_response :success
    page2_html = response.body

    assert_includes page2_html, "Showing <strong>21&ndash;28</strong> of <strong>28</strong> submissions"
    assert_includes page2_html, "Page <strong>2</strong> of <strong>2</strong>"
    assert_includes page2_html, "&larr; Previous"
    assert_includes page2_html, "pagination-next-disabled"

    # Verify Page 1 and Page 2 records are completely disjoint
    created_ids.each do |sub_id|
      in_page1 = page1_html.include?("##{sub_id}")
      in_page2 = page2_html.include?("##{sub_id}")
      assert in_page1 ^ in_page2, "Submission ##{sub_id} should appear in either Page 1 or Page 2, not both or neither!"
    end
  end

  test "pagination beyond last page renders safe empty result without exception" do
    sign_in_as(@user_a)

    get survey_submissions_path(@survey_a1, page: 999)
    assert_response :success

    # Safely displays empty table with zero records rendered
    assert_not_includes response.body, "ActiveRecord::RecordNotFound"
    assert_not_includes response.body, "Pagy::OptionError"
  end

  test "pagination sanitizes invalid page parameters safely" do
    sign_in_as(@user_a)

    # Non-numeric string
    get survey_submissions_path(@survey_a1, page: "abc")
    assert_response :success
    assert_includes response.body, "Survey Responses"

    # Zero
    get survey_submissions_path(@survey_a1, page: 0)
    assert_response :success

    # Negative
    get survey_submissions_path(@survey_a1, page: -5)
    assert_response :success

    # Empty string
    get survey_submissions_path(@survey_a1, page: "")
    assert_response :success
  end

  test "pagination enforces maximum limit cap and prevents arbitrary huge per_page loads" do
    sign_in_as(@user_a)

    # Attempt to request 100,000 items per page
    get survey_submissions_path(@survey_a1, per_page: 100_000)
    assert_response :success

    # Capped at MAX_PER_PAGE (100)
    assert_includes response.body, "Survey Responses"
  end

  test "pagination strictly enforces tenant isolation across pages" do
    sign_in_as(@user_a)

    # Attempt to access page 2 of Customer B's survey
    get survey_submissions_path(@survey_b1, page: 2)
    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found."
  end

  test "pagination with large dataset (100 submissions) calculates exact page counts and bounds" do
    sign_in_as(@user_a)

    # Add 100 submissions
    100.times do |i|
      sub = @survey_a1.submissions.create!(submitted_at: (i + 1).days.ago)
      sub.answers.create!(question: @q_text, text_value: "Large #{i}")
    end

    total = @survey_a1.submissions.count # 103 total (3 initial + 100)
    expected_pages = (total / 20.0).ceil # 6 pages

    # Page 1
    get survey_submissions_path(@survey_a1, page: 1)
    assert_response :success
    assert_includes response.body, "Showing <strong>1&ndash;20</strong> of <strong>#{total}</strong> submissions"
    assert_includes response.body, "Page <strong>1</strong> of <strong>#{expected_pages}</strong>"

    # Page 6 (final page)
    get survey_submissions_path(@survey_a1, page: expected_pages)
    assert_response :success
    assert_includes response.body, "Showing <strong>101&ndash;#{total}</strong> of <strong>#{total}</strong> submissions"
    assert_includes response.body, "Page <strong>#{expected_pages}</strong> of <strong>#{expected_pages}</strong>"
  end
end
