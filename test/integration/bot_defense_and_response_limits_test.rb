# frozen_string_literal: true

require "test_helper"

class BotDefenseAndResponseLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @customer_a = Customer.create!(name: "Acme Cloud")
    @customer_b = Customer.create!(name: "Beta Solutions")

    @user_a = @customer_a.users.create!(
      name: "Alice Acme",
      email: "alice@acme.test",
      password: "ChangeMe123!"
    )
    @user_b = @customer_b.users.create!(
      name: "Bob Beta",
      email: "bob@beta.test",
      password: "ChangeMe123!"
    )

    CaptchaVerifier.mock_result = nil
    CaptchaVerifier.request_handler = nil
  end

  teardown do
    CaptchaVerifier.mock_result = nil
    CaptchaVerifier.request_handler = nil
  end

  # =========================================================================
  # FEATURE A: CAPTCHA / Bot Defense Integration Tests
  # =========================================================================

  test "valid CAPTCHA allows submission when bot defense is enforced" do
    survey = @customer_a.surveys.create!(title: "Secured Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    CaptchaVerifier.with_enforced do
      CaptchaVerifier.with_mock(success: true) do
        assert_difference -> { survey.submissions.count } => 1 do
          post submit_public_survey_path(survey.public_token), params: {
            "cf-turnstile-response" => "valid-token-xyz",
            answers: { q.id.to_s => "Authentic human response" }
          }
          assert_redirected_to public_survey_success_path(survey.public_token)
        end
      end
    end
  end

  test "missing CAPTCHA rejects submission and creates zero records" do
    survey = @customer_a.surveys.create!(title: "Secured Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    CaptchaVerifier.with_enforced do
      assert_no_difference [ -> { survey.submissions.count }, -> { Answer.count } ] do
        post submit_public_survey_path(survey.public_token), params: {
          answers: { q.id.to_s => "Automated bot post" }
        }
        assert_response :unprocessable_entity
        assert_includes response.body, "Please complete the CAPTCHA challenge."
      end
    end
  end

  test "invalid CAPTCHA rejects submission and creates zero records" do
    survey = @customer_a.surveys.create!(title: "Secured Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    CaptchaVerifier.with_enforced do
      CaptchaVerifier.with_mock(success: false, error_message: "We couldn't verify that you're human. Please try again.") do
        assert_no_difference [ -> { survey.submissions.count }, -> { Answer.count } ] do
          post submit_public_survey_path(survey.public_token), params: {
            "cf-turnstile-response" => "invalid-token",
            answers: { q.id.to_s => "Spam submission" }
          }
          assert_response :unprocessable_entity
          assert_includes CGI.unescapeHTML(response.body), "We couldn't verify that you're human. Please try again."
        end
      end
    end
  end

  test "expired CAPTCHA rejects submission with friendly expiration message" do
    survey = @customer_a.surveys.create!(title: "Secured Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    CaptchaVerifier.with_enforced do
      CaptchaVerifier.with_mock(success: false, error_message: "CAPTCHA challenge expired. Please verify again.") do
        assert_no_difference -> { survey.submissions.count } do
          post submit_public_survey_path(survey.public_token), params: {
            "cf-turnstile-response" => "expired-token",
            answers: { q.id.to_s => "Late response" }
          }
          assert_response :unprocessable_entity
          assert_includes response.body, "CAPTCHA challenge expired. Please verify again."
        end
      end
    end
  end

  test "provider failure safely fails closed and blocks submission" do
    survey = @customer_a.surveys.create!(title: "Secured Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    CaptchaVerifier.with_enforced do
      old_secret = ENV["TURNSTILE_SECRET_KEY"]
      ENV["TURNSTILE_SECRET_KEY"] = "secret-key-123"
      CaptchaVerifier.request_handler = ->(*) { raise SocketError, "Failed to reach Cloudflare" }

      assert_no_difference -> { survey.submissions.count } do
        post submit_public_survey_path(survey.public_token), params: {
          "cf-turnstile-response" => "any-token",
          answers: { q.id.to_s => "Response during outage" }
        }
        assert_response :unprocessable_entity
        assert_includes CGI.unescapeHTML(response.body), "We couldn't verify that you're human. Please try again."
      end
    ensure
      ENV["TURNSTILE_SECRET_KEY"] = old_secret
      CaptchaVerifier.request_handler = nil
    end
  end

  test "authenticated customer dashboard pages are unaffected by CAPTCHA" do
    sign_in_as(@user_a)

    # Creating a survey does not require CAPTCHA
    assert_difference -> { @customer_a.surveys.count } => 1 do
      post surveys_path, params: {
        survey: {
          title: "Dashboard Created Survey",
          questions_attributes: { "0" => { question_text: "Q1", question_type: "text", position: 1 } }
        }
      }
    end
    assert_response :redirect

    # Managing surveys unaffected
    survey = @customer_a.surveys.last
    get survey_path(survey)
    assert_response :success
  end

  test "public survey GET renders Turnstile widget when CAPTCHA is enabled" do
    survey = @customer_a.surveys.create!(title: "Widget Survey", status: :published, published_at: Time.current)
    survey.questions.create!(question_text: "Q", question_type: :text, position: 1)

    CaptchaVerifier.with_enforced do
      get public_survey_path(survey.public_token)
      assert_response :success
      assert_includes response.body, "cf-turnstile"
      assert_includes response.body, CaptchaVerifier.site_key
      assert_includes response.body, "challenges.cloudflare.com/turnstile"
    end
  end

  test "rate limiting remains active alongside CAPTCHA" do
    survey = @customer_a.surveys.create!(title: "Rate Limit + CAPTCHA", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Q", question_type: :text, position: 1)

    CaptchaVerifier.with_mock(success: true) do
      # Submit up to the 10 req/min limit
      10.times do
        post submit_public_survey_path(survey.public_token), params: {
          "cf-turnstile-response" => "valid",
          answers: { q.id.to_s => "Valid Answer" }
        }
        assert_redirected_to public_survey_success_path(survey.public_token)
      end

      # 11th request triggers rate limit HTTP 429
      post submit_public_survey_path(survey.public_token), params: {
        "cf-turnstile-response" => "valid",
        answers: { q.id.to_s => "Valid Answer" }
      }
      assert_response :too_many_requests
    end
  end

  # =========================================================================
  # FEATURE B: Multiple Response Cookies & Device Limitation Tests
  # =========================================================================

  test "survey without limit allows multiple submissions from same browser" do
    survey = @customer_a.surveys.create!(
      title: "Open Multi-Response Survey",
      limit_one_response_per_device: false,
      status: :published,
      published_at: Time.current
    )
    q = survey.questions.create!(question_text: "Q1", question_type: :text, position: 1, required: true)

    # 3 submissions from same browser session
    3.times do |i|
      assert_difference -> { survey.submissions.count } => 1 do
        post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Response #{i}" } }
        assert_redirected_to public_survey_success_path(survey.public_token)
      end
    end

    assert_equal 3, survey.submissions.count
  end

  test "survey with limit_one_response_per_device blocks second submission from same browser" do
    survey = @customer_a.surveys.create!(
      title: "One Response Per Device Survey",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    q = survey.questions.create!(question_text: "Q1", question_type: :text, position: 1, required: true)

    # First submission succeeds and sets signed cookie
    assert_difference -> { survey.submissions.count } => 1 do
      post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "First Response" } }
      assert_redirected_to public_survey_success_path(survey.public_token)
    end

    # Verify cookie was set
    assert cookies[:survey_respondent_token].present?
    sub = survey.submissions.last
    assert_not_nil sub.respondent_token_digest

    # Second submission from same browser session is rejected
    assert_no_difference [ -> { survey.submissions.count }, -> { Answer.count } ] do
      post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Second Response" } }
      assert_response :unprocessable_entity
      assert_includes response.body, "You have already submitted this survey from this browser."
    end
  end

  test "different browser context can submit to one-response survey" do
    survey = @customer_a.surveys.create!(
      title: "One Response Per Device Survey",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    q = survey.questions.create!(question_text: "Q1", question_type: :text, position: 1, required: true)

    # Browser 1 submits
    post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Browser 1" } }
    assert_redirected_to public_survey_success_path(survey.public_token)
    assert_equal 1, survey.submissions.count

    # Simulate Browser 2 (different session/browser context)
    browser2 = open_session

    assert_difference -> { survey.submissions.count } => 1 do
      browser2.post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Browser 2" } }
      assert_equal 302, browser2.response.status
    end
    assert_equal 2, survey.submissions.count
  end

  test "cookie tampering is safely handled and does not crash" do
    survey = @customer_a.surveys.create!(
      title: "One Response Per Device Survey",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    q = survey.questions.create!(question_text: "Q1", question_type: :text, position: 1, required: true)

    # Set tampered/unsigned raw cookie
    cookies[:survey_respondent_token] = "tampered-raw-string-without-valid-signature"

    # Rails signed cookie reader returns nil for invalid signatures and generates a new token
    assert_difference -> { survey.submissions.count } => 1 do
      post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Post Tampering" } }
      assert_redirected_to public_survey_success_path(survey.public_token)
    end
  end

  test "cross survey cookie independence: Survey A submission does not block Survey B" do
    survey_a = @customer_a.surveys.create!(
      title: "Survey Alpha",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    qa = survey_a.questions.create!(question_text: "QA", question_type: :text, position: 1, required: true)

    survey_b = @customer_b.surveys.create!(
      title: "Survey Beta",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    qb = survey_b.questions.create!(question_text: "QB", question_type: :text, position: 1, required: true)

    # Submit to Survey A
    post submit_public_survey_path(survey_a.public_token), params: { answers: { qa.id.to_s => "Response A" } }
    assert_redirected_to public_survey_success_path(survey_a.public_token)
    assert_equal 1, survey_a.submissions.count

    # Same browser submits to Survey B: allowed because digests are scoped to survey_id
    assert_difference -> { survey_b.submissions.count } => 1 do
      post submit_public_survey_path(survey_b.public_token), params: { answers: { qb.id.to_s => "Response B" } }
      assert_redirected_to public_survey_success_path(survey_b.public_token)
    end
    assert_equal 1, survey_b.submissions.count

    # But subsequent attempt to Survey A remains blocked
    post submit_public_survey_path(survey_a.public_token), params: { answers: { qa.id.to_s => "Response A2" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "You have already submitted this survey from this browser."
  end

  test "concurrent race condition on duplicate submissions is handled by database constraint" do
    survey = @customer_a.surveys.create!(
      title: "Race Condition Survey",
      limit_one_response_per_device: true,
      status: :published,
      published_at: Time.current
    )
    q = survey.questions.create!(question_text: "Question", question_type: :text, position: 1, required: true)

    token = "simulated-fixed-token-xyz"
    digest = Survey.respondent_token_digest(survey.id, token)

    # First submission with digest succeeds
    res1 = SubmitSurvey.new(survey, { q.id.to_s => "First" }, respondent_token_digest: digest).call
    assert_predicate res1, :success?
    assert_predicate res1.submission, :persisted?

    # Second concurrent submission with exact same digest is rejected gracefully
    res2 = SubmitSurvey.new(survey, { q.id.to_s => "Second Concurrent" }, respondent_token_digest: digest).call
    assert_not res2.success?
    assert_includes res2.errors, "You have already submitted this survey from this browser."
    assert_equal 1, survey.submissions.count
  end

  # =========================================================================
  # FULL END-TO-END WORKFLOW (Section 29)
  # =========================================================================

  test "complete end to end workflow: create survey with one-response mode, publish, submit with CAPTCHA, reject second" do
    # 1. Login as Customer A user
    sign_in_as(@user_a)

    # 2. Create survey with limit_one_response_per_device enabled
    survey_params = {
      survey: {
        title: "Exclusive Device Survey",
        description: "One response per browser.",
        limit_one_response_per_device: "1",
        questions_attributes: {
          "0" => { question_text: "Your feedback?", question_type: "text", position: 1, required: "1" }
        }
      }
    }

    assert_difference -> { @customer_a.surveys.count } => 1 do
      post surveys_path, params: survey_params
    end
    survey = @customer_a.surveys.last
    assert_predicate survey, :limit_one_response_per_device?

    # 3. Publish survey
    post publish_survey_path(survey)
    assert_redirected_to survey_path(survey)
    survey.reload
    assert_predicate survey, :published?

    # 4. Logout completely
    delete logout_path
    assert_nil session[:user_id]

    # 5. Open public survey URL
    get public_survey_path(survey.public_token)
    assert_response :success
    assert_includes response.body, "One response per device"

    # 6. Submit with valid CAPTCHA
    q = survey.questions.first
    CaptchaVerifier.with_enforced do
      CaptchaVerifier.with_mock(success: true) do
        assert_difference -> { survey.submissions.count } => 1 do
          post submit_public_survey_path(survey.public_token), params: {
            "cf-turnstile-response" => "mock-human-token",
            answers: { q.id.to_s => "Human feedback" }
          }
          assert_redirected_to public_survey_success_path(survey.public_token)
        end
      end
    end

    # 7. Verify submission in database
    submission = survey.submissions.last
    assert_not_nil submission.respondent_token_digest

    # 8. Submit again from the same browser context
    CaptchaVerifier.with_enforced do
      CaptchaVerifier.with_mock(success: true) do
        assert_no_difference -> { survey.submissions.count } do
          post submit_public_survey_path(survey.public_token), params: {
            "cf-turnstile-response" => "mock-human-token-2",
            answers: { q.id.to_s => "Duplicate attempt" }
          }
          assert_response :unprocessable_entity
          assert_includes response.body, "You have already submitted this survey from this browser."
        end
      end
    end
  end
end
