# frozen_string_literal: true

require "test_helper"

class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    @customer_a = Customer.create!(name: "RateLimit Corp A")
    @customer_b = Customer.create!(name: "RateLimit Corp B")

    @user_a = User.create!(
      customer: @customer_a,
      name: "Alice A",
      email: "alice.rl@example.com",
      password: "Password123!"
    )

    @survey_a = Survey.create!(
      customer: @customer_a,
      title: "Survey A",
      status: :published,
      published_at: Time.current
    )
    @survey_a.questions.create!(question_text: "Feedback?", question_type: :text, position: 1)

    @survey_b = Survey.create!(
      customer: @customer_b,
      title: "Survey B",
      status: :published,
      published_at: Time.current
    )
    @survey_b.questions.create!(question_text: "Rate us", question_type: :number, position: 1)
  end

  # Test A — Normal access
  test "test_a_normal_user_can_access_public_survey" do
    get public_survey_path(@survey_a.public_token)
    assert_response :success
    assert_includes response.body, "Survey A"
  end

  # Test B — Normal submission
  test "test_b_normal_respondent_can_submit_survey" do
    q = @survey_a.questions.first
    post submit_public_survey_path(@survey_a.public_token), params: {
      answers: { q.id.to_s => "Great platform!" }
    }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Thank you"
  end

  # Test C — Excessive GET requests
  test "test_c_excessive_get_requests_trigger_429" do
    ip = "192.168.1.100"

    60.times do
      get public_survey_path(@survey_a.public_token), headers: { "REMOTE_ADDR" => ip }
      assert_response :success
    end

    # 61st request exceeds the limit
    get public_survey_path(@survey_a.public_token), headers: { "REMOTE_ADDR" => ip }
    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
    assert_includes response.body, "Too Many Requests"
  end

  # Test D — Excessive POST submissions
  test "test_d_excessive_post_submissions_trigger_429" do
    ip = "192.168.1.101"
    q = @survey_a.questions.first

    10.times do |i|
      post submit_public_survey_path(@survey_a.public_token),
           params: { answers: { q.id.to_s => "Submission #{i}" } },
           headers: { "REMOTE_ADDR" => ip }
      assert_response :redirect
    end

    # 11th submission exceeds the limit
    post submit_public_survey_path(@survey_a.public_token),
         params: { answers: { q.id.to_s => "Spam submission" } },
         headers: { "REMOTE_ADDR" => ip }
    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
    assert_includes response.body, "Too Many Requests"
  end

  # Test E — Rate limit isolation between surveys
  test "test_e_rate_limit_isolation_across_surveys" do
    ip = "192.168.1.102"
    q_a = @survey_a.questions.first
    q_b = @survey_b.questions.first

    # Flood Survey A up to rate limit
    10.times do |i|
      post submit_public_survey_path(@survey_a.public_token),
           params: { answers: { q_a.id.to_s => "Resp #{i}" } },
           headers: { "REMOTE_ADDR" => ip }
      assert_response :redirect
    end

    # 11th submission to Survey A is throttled
    post submit_public_survey_path(@survey_a.public_token),
         params: { answers: { q_a.id.to_s => "Throttled" } },
         headers: { "REMOTE_ADDR" => ip }
    assert_response :too_many_requests

    # Same IP can still submit to Survey B without being blocked
    post submit_public_survey_path(@survey_b.public_token),
         params: { answers: { q_b.id.to_s => "5" } },
         headers: { "REMOTE_ADDR" => ip }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # Test F — Tenant isolation remains intact
  test "test_f_tenant_isolation_remains_intact_under_rate_limiting" do
    sign_in_as(@user_a, password: "Password123!")

    # User A accesses their own dashboard & survey
    get surveys_path
    assert_response :success
    assert_includes response.body, "Survey A"
    refute_includes response.body, "Survey B"

    # User A cannot access Survey B (Customer B)
    get survey_path(@survey_b)
    assert_response :redirect
    assert_equal "Survey not found.", flash[:alert]
  end
end
