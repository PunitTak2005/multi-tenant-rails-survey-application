# frozen_string_literal: true

require "test_helper"

class Requirement2PublicSurveySubmissionTest < ActionDispatch::IntegrationTest
  setup do
    @customer_a = Customer.create!(name: "Alpha Corp")
    @customer_b = Customer.create!(name: "Beta Industries")

    @user_a = @customer_a.users.create!(
      name: "Alice Alpha",
      email: "alice@alpha.test",
      password: "ChangeMe123!"
    )
    @user_b = @customer_b.users.create!(
      name: "Bob Beta",
      email: "bob@beta.test",
      password: "ChangeMe123!"
    )
  end

  # =========================================================================
  # 1. Primary Success Criterion: Full End-to-End Workflow (Sections 1, 40)
  # =========================================================================
  test "full end to end workflow from customer authoring to anonymous submission and dashboard verification" do
    # Step 1: Customer User logs in
    sign_in_as(@user_a)
    assert_equal @user_a.id, session[:user_id]

    # Step 2 & 3: Create Survey with 4 questions (Text, Number, Multiple Choice, Optional Text)
    survey_params = {
      survey: {
        title: "Developer Feedback Survey",
        description: "Official annual developer community survey.",
        questions_attributes: {
          "0" => {
            question_text: "What is your name?",
            question_type: "text",
            position: 1,
            required: "1"
          },
          "1" => {
            question_text: "How many years of experience do you have?",
            question_type: "number",
            position: 2,
            required: "1"
          },
          "2" => {
            question_text: "Which programming language do you prefer?",
            question_type: "multiple_choice",
            position: 3,
            required: "1",
            question_options_attributes: {
              "0" => { label: "Ruby", position: 1 },
              "1" => { label: "JavaScript", position: 2 },
              "2" => { label: "Python", position: 3 },
              "3" => { label: "Java", position: 4 }
            }
          },
          "3" => {
            question_text: "Tell us anything else.",
            question_type: "text",
            position: 4,
            required: "0"
          }
        }
      }
    }

    assert_difference -> { @customer_a.surveys.count } => 1 do
      post surveys_path, params: survey_params
    end
    survey = @customer_a.surveys.last
    assert_redirected_to survey_path(survey)

    # Step 4: Survey is initially saved in draft
    assert_predicate survey, :draft?
    assert_equal 4, survey.questions.count

    # Step 5: Publish Survey
    post publish_survey_path(survey)
    assert_redirected_to survey_path(survey)
    survey.reload
    assert_predicate survey, :published?
    assert_not_nil survey.published_at
    assert_not_nil survey.public_token

    # Step 6: Verify public URL structure
    public_token = survey.public_token
    assert_predicate public_token.length, :positive?
    public_url_path = public_survey_path(public_token)
    assert_equal "/s/#{public_token}", public_url_path

    # Step 7: Customer logs out completely
    delete logout_path
    assert_nil session[:user_id]

    # Step 8 & 9: Open public survey URL WITHOUT ANY LOGIN
    get public_url_path
    assert_response :success
    assert_includes response.body, "Developer Feedback Survey"
    assert_includes response.body, "Official annual developer community survey."
    assert_includes response.body, "What is your name?"
    assert_includes response.body, "How many years of experience do you have?"
    assert_includes response.body, "Which programming language do you prefer?"
    assert_includes response.body, "Ruby"
    assert_includes response.body, "JavaScript"
    assert_includes response.body, "Python"
    assert_includes response.body, "Java"
    assert_includes response.body, "Tell us anything else."
    assert_includes response.body, "Submit Survey"

    # Step 10: Verify respondent is not authenticated
    assert_nil session[:user_id]

    # Step 11: Identify target question and option records
    q_name = survey.questions.find_by!(question_text: "What is your name?")
    q_years = survey.questions.find_by!(question_text: "How many years of experience do you have?")
    q_lang = survey.questions.find_by!(question_text: "Which programming language do you prefer?")
    opt_python = q_lang.question_options.find_by!(label: "Python")
    q_comments = survey.questions.find_by!(question_text: "Tell us anything else.")

    # Record database counts before submission
    sub_count_before = survey.submissions.count
    ans_count_before = Answer.count

    # Step 12: Enter Answers and Submit
    submitted_payload = {
      q_name.id.to_s => "John Smith",
      q_years.id.to_s => "5",
      q_lang.id.to_s => opt_python.id.to_s,
      q_comments.id.to_s => "Great survey."
    }

    post submit_public_survey_path(public_token), params: { answers: submitted_payload }
    assert_redirected_to public_survey_success_path(public_token)

    # Step 13: Follow redirect and verify success confirmation
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Thank you!"
    assert_includes response.body, "Your survey response has been submitted successfully."
    # Ensure no internal database IDs or private details are leaked to respondent
    assert_not_includes response.body, "alice@alpha.test"
    assert_not_includes response.body, "Alpha Corp"

    # Step 14 & 15: Direct Database Verification
    assert_equal sub_count_before + 1, survey.submissions.count
    assert_equal ans_count_before + 4, Answer.count

    submission = survey.submissions.last
    assert_equal survey.id, submission.survey_id
    assert_not_nil submission.submitted_at
    assert_not_nil submission.created_at

    # Step 16: Verify Answer records and typed values
    ans_name = submission.answers.find_by!(question_id: q_name.id)
    assert_equal "John Smith", ans_name.text_value
    assert_nil ans_name.number_value
    assert_nil ans_name.selected_option_id

    ans_years = submission.answers.find_by!(question_id: q_years.id)
    assert_equal BigDecimal("5"), ans_years.number_value
    assert_nil ans_years.text_value
    assert_nil ans_years.selected_option_id

    ans_lang = submission.answers.find_by!(question_id: q_lang.id)
    assert_equal opt_python.id, ans_lang.selected_option_id
    assert_equal opt_python, ans_lang.selected_option
    assert_equal "Python", ans_lang.display_value
    assert_nil ans_lang.text_value
    assert_nil ans_lang.number_value

    ans_comments = submission.answers.find_by!(question_id: q_comments.id)
    assert_equal "Great survey.", ans_comments.text_value
    assert_nil ans_comments.number_value
    assert_nil ans_comments.selected_option_id

    # Step 17: Customer A logs back into the dashboard
    sign_in_as(@user_a)
    get survey_submissions_path(survey)
    assert_response :success
    assert_includes response.body, "##{submission.id}"
    assert_includes response.body, "4 answers"

    # Step 18: View response details
    get survey_submission_path(survey, submission)
    assert_response :success
    assert_includes response.body, "John Smith"
    assert_includes response.body, "5.0"
    assert_includes response.body, "Python"
    assert_includes response.body, "Great survey."

    # Step 19: Verify Customer B cannot access Customer A's submission data
    sign_in_as(@user_b)
    get survey_submissions_path(survey)
    assert_redirected_to surveys_path

    get survey_submission_path(survey, submission)
    assert_redirected_to surveys_path
  end

  # =========================================================================
  # 2. Published vs Unpublished & Token Routing (Sections 8, 18, 19, 20)
  # =========================================================================
  test "published vs unpublished access and invalid or modified token protection" do
    # Survey A is published
    survey_a = @customer_a.surveys.create!(title: "Published Survey", status: :published, published_at: Time.current)
    survey_a.questions.create!(question_text: "Question 1", question_type: :text, position: 1)

    # Survey B is draft
    survey_b = @customer_a.surveys.create!(title: "Draft Survey", status: :draft)
    survey_b.questions.create!(question_text: "Question 1", question_type: :text, position: 1)

    # Published Survey A accessible without authentication
    get public_survey_path(survey_a.public_token)
    assert_response :success
    assert_includes response.body, "Published Survey"

    # Draft Survey B blocked with 404 Not Found
    get public_survey_path(survey_b.public_token)
    assert_response :not_found

    # Direct submission to draft survey blocked with 404
    post submit_public_survey_path(survey_b.public_token), params: { answers: { "1" => "Test" } }
    assert_response :not_found

    # Nonexistent token returns 404 without leaking stack trace
    get public_survey_path("nonexistent-token-99999")
    assert_response :not_found

    # Modified token returns 404
    get public_survey_path("#{survey_a.public_token}-mod")
    assert_response :not_found

    # Token enumeration verification: tokens are random and non-sequential
    assert_no_match(/\A\d+\z/, survey_a.public_token)
    assert_operator survey_a.public_token.length, :>=, 16
  end

  # =========================================================================
  # 3. Numeric Semantics and Malformed Number Validations (Sections 14, 23)
  # =========================================================================
  test "number question accepts valid integers and decimals, and rejects malformed inputs" do
    survey = @customer_a.surveys.create!(title: "Numeric Test Survey", status: :published, published_at: Time.current)
    q_num = survey.questions.create!(question_text: "Score", question_type: :number, position: 1, required: true)

    # Test valid numeric values: 0, 1, 10, 25, 5.5
    valid_numbers = [ "0", "1", "10", "25", "5.5" ]
    valid_numbers.each do |num_str|
      assert_difference -> { survey.submissions.count } => 1 do
        post submit_public_survey_path(survey.public_token), params: { answers: { q_num.id.to_s => num_str } }
        assert_redirected_to public_survey_success_path(survey.public_token)
      end

      last_sub = survey.submissions.last
      ans = last_sub.answers.find_by!(question_id: q_num.id)
      assert_equal BigDecimal(num_str), ans.number_value
    end

    # Test malformed numbers: "abc", "12abc", "xyz"
    malformed_inputs = [ "abc", "12abc", "xyz", "12.34.56" ]
    malformed_inputs.each do |bad_val|
      assert_no_difference -> { survey.submissions.count } do
        post submit_public_survey_path(survey.public_token), params: { answers: { q_num.id.to_s => bad_val } }
        assert_response :unprocessable_entity
        assert_includes response.body, "must be a valid number"
      end
    end
  end

  # =========================================================================
  # 4. Required Field Validation & Optional Question Handling (Sections 21, 22)
  # =========================================================================
  test "required field validations block submission while optional questions can be omitted" do
    survey = @customer_a.surveys.create!(title: "Validation Survey", status: :published, published_at: Time.current)
    q1 = survey.questions.create!(question_text: "Required Name", question_type: :text, position: 1, required: true)
    q2 = survey.questions.create!(question_text: "Required Rating", question_type: :number, position: 2, required: true)
    q3 = survey.questions.create!(question_text: "Required Choice", question_type: :multiple_choice, position: 3, required: true)
    opt = q3.question_options.create!(label: "Option 1", position: 1)
    q4_opt = survey.questions.create!(question_text: "Optional Notes", question_type: :text, position: 4, required: false)

    # Missing required name
    assert_no_difference -> { survey.submissions.count } do
      post submit_public_survey_path(survey.public_token), params: {
        answers: { q2.id.to_s => "10", q3.id.to_s => opt.id.to_s }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "required"
    end

    # Missing required rating
    assert_no_difference -> { survey.submissions.count } do
      post submit_public_survey_path(survey.public_token), params: {
        answers: { q1.id.to_s => "Alice", q3.id.to_s => opt.id.to_s }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "required"
    end

    # Missing required multiple choice
    assert_no_difference -> { survey.submissions.count } do
      post submit_public_survey_path(survey.public_token), params: {
        answers: { q1.id.to_s => "Alice", q2.id.to_s => "10" }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "required"
    end

    # All required fields missing
    assert_no_difference -> { survey.submissions.count } do
      post submit_public_survey_path(survey.public_token), params: { answers: {} }
      assert_response :unprocessable_entity
      assert_includes response.body, "required"
    end

    # Required questions provided, optional question left completely blank
    assert_difference -> { survey.submissions.count } => 1, -> { Answer.count } => 3 do
      post submit_public_survey_path(survey.public_token), params: {
        answers: {
          q1.id.to_s => "Alice",
          q2.id.to_s => "10",
          q3.id.to_s => opt.id.to_s,
          q4_opt.id.to_s => "" # Blank optional text
        }
      }
      assert_redirected_to public_survey_success_path(survey.public_token)
    end

    sub = survey.submissions.last
    assert_equal 3, sub.answers.count
    assert_nil sub.answers.find_by(question_id: q4_opt.id)
  end

  # =========================================================================
  # 5. Cross-Question and Cross-Survey Attacks (Sections 16, 17)
  # =========================================================================
  test "server blocks cross question option hijacking and cross survey question injection" do
    survey_a = @customer_a.surveys.create!(title: "Survey Alpha", status: :published, published_at: Time.current)
    qa1 = survey_a.questions.create!(question_text: "Alpha Q1 Choice", question_type: :multiple_choice, position: 1, required: true)
    qa1_opt1 = qa1.question_options.create!(label: "Alpha Opt 1", position: 1)

    qa2 = survey_a.questions.create!(question_text: "Alpha Q2 Choice", question_type: :multiple_choice, position: 2, required: true)
    qa2_opt2 = qa2.question_options.create!(label: "Alpha Opt 2", position: 1)

    survey_b = @customer_b.surveys.create!(title: "Survey Beta", status: :published, published_at: Time.current)
    qb1 = survey_b.questions.create!(question_text: "Beta Question", question_type: :text, position: 1, required: true)

    # Attack 1: Cross-Question Option Hijacking (Submitting qa2's option for qa1)
    assert_no_difference -> { survey_a.submissions.count } do
      post submit_public_survey_path(survey_a.public_token), params: {
        answers: {
          qa1.id.to_s => qa2_opt2.id.to_s, # Invalid option belonging to different question!
          qa2.id.to_s => qa2_opt2.id.to_s
        }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "invalid"
    end

    # Attack 2: Cross-Survey Question Injection (Injecting qb1 into survey_a submission)
    # The submission service ignores foreign questions not belonging to survey_a
    assert_difference -> { survey_a.submissions.count } => 1 do
      post submit_public_survey_path(survey_a.public_token), params: {
        answers: {
          qa1.id.to_s => qa1_opt1.id.to_s,
          qa2.id.to_s => qa2_opt2.id.to_s,
          qb1.id.to_s => "Malicious Cross Survey Injection"
        }
      }
      assert_redirected_to public_survey_success_path(survey_a.public_token)
    end

    # Verify no answer was created for Survey B's question
    sub = survey_a.submissions.last
    assert_equal 2, sub.answers.count
    assert_nil Answer.find_by(question_id: qb1.id)
  end

  # =========================================================================
  # 6. Parameter Tampering & Mass Assignment Guard (Section 24)
  # =========================================================================
  test "extra parameters cannot alter survey ownership or inject user tenant identity" do
    survey = @customer_a.surveys.create!(title: "Tamper Test", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Your Name", question_type: :text, position: 1, required: true)

    tampered_params = {
      answers: { q.id.to_s => "Legitimate Name" },
      survey_id: 99_999,
      customer_id: @customer_b.id,
      user_id: @user_b.id,
      role: "admin"
    }

    assert_difference -> { survey.submissions.count } => 1 do
      post submit_public_survey_path(survey.public_token), params: tampered_params
      assert_redirected_to public_survey_success_path(survey.public_token)
    end

    submission = survey.submissions.last
    assert_equal survey.id, submission.survey_id
    assert_equal @customer_a.id, survey.customer_id
  end

  # =========================================================================
  # 7. Multiple Respondents and Duplicate Submissions (Sections 26, 27)
  # =========================================================================
  test "multiple respondents and identical duplicate answers are persisted independently" do
    survey = @customer_a.surveys.create!(title: "Multi Respondent Survey", status: :published, published_at: Time.current)
    q_name = survey.questions.create!(question_text: "Name", question_type: :text, position: 1, required: true)

    # 3 distinct submissions
    names = [ "Respondent One", "Respondent Two", "Respondent Three" ]
    names.each do |n|
      post submit_public_survey_path(survey.public_token), params: { answers: { q_name.id.to_s => n } }
      assert_redirected_to public_survey_success_path(survey.public_token)
    end
    assert_equal 3, survey.submissions.count

    # Duplicate submission with identical answer is also stored independently
    post submit_public_survey_path(survey.public_token), params: { answers: { q_name.id.to_s => "Respondent Three" } }
    assert_redirected_to public_survey_success_path(survey.public_token)
    assert_equal 4, survey.submissions.count

    # Confirm unique IDs and individual answers
    submission_ids = survey.submissions.pluck(:id)
    assert_equal 4, submission_ids.uniq.count
  end

  # =========================================================================
  # 8. Transactional Atomicity and Rollback Test (Section 28)
  # =========================================================================
  test "transactional rollback guarantees zero partial submissions on validation failure" do
    survey = @customer_a.surveys.create!(title: "Atomic Survey", status: :published, published_at: Time.current)
    q_txt = survey.questions.create!(question_text: "Text Q", question_type: :text, position: 1, required: true)
    q_num = survey.questions.create!(question_text: "Num Q", question_type: :number, position: 2, required: true)

    sub_count_before = Submission.count
    ans_count_before = Answer.count

    # Payload with valid text but completely invalid number
    invalid_payload = {
      q_txt.id.to_s => "Valid Text Answer",
      q_num.id.to_s => "NOT_A_NUMBER"
    }

    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      post submit_public_survey_path(survey.public_token), params: { answers: invalid_payload }
      assert_response :unprocessable_entity
    end

    assert_equal sub_count_before, Submission.count
    assert_equal ans_count_before, Answer.count
  end

  # =========================================================================
  # 9. Tenant Isolation in Results & Private Submissions (Sections 25, 30)
  # =========================================================================
  test "public submission data respects tenant isolation in customer dashboard" do
    survey_a = @customer_a.surveys.create!(title: "Alpha Survey", status: :published, published_at: Time.current)
    qa = survey_a.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    survey_b = @customer_b.surveys.create!(title: "Beta Survey", status: :published, published_at: Time.current)
    qb = survey_b.questions.create!(question_text: "Feedback", question_type: :text, position: 1, required: true)

    # Submit to Survey A
    post submit_public_survey_path(survey_a.public_token), params: { answers: { qa.id.to_s => "Alpha Feedback" } }
    sub_a = survey_a.submissions.last

    # Submit to Survey B
    post submit_public_survey_path(survey_b.public_token), params: { answers: { qb.id.to_s => "Beta Feedback" } }
    sub_b = survey_b.submissions.last

    # User A logs in
    sign_in_as(@user_a)
    get survey_submissions_path(survey_a)
    assert_response :success
    assert_includes response.body, "##{sub_a.id}"

    # User A cannot access User B's survey submissions
    get survey_submissions_path(survey_b)
    assert_redirected_to surveys_path

    get survey_submission_path(survey_b, sub_b)
    assert_redirected_to surveys_path

    # Unauthenticated visitor cannot access private submissions directly
    delete logout_path
    get survey_submissions_path(survey_a)
    assert_redirected_to login_path

    get survey_submission_path(survey_a, sub_a)
    assert_redirected_to login_path
  end

  # =========================================================================
  # 10. XSS Prevention & Public Confirmation Privacy (Sections 30, 31)
  # =========================================================================
  test "xss script tags are escaped and confirmation screen leaks no private data" do
    survey = @customer_a.surveys.create!(title: "XSS Survey", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Comments", question_type: :text, position: 1, required: true)

    xss_payload = "<script>alert('pwned')</script>"
    post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => xss_payload } }
    assert_redirected_to public_survey_success_path(survey.public_token)

    # Confirmation page check
    follow_redirect!
    assert_response :success
    assert_not_includes response.body, "<script>alert('pwned')</script>"
    assert_not_includes response.body, "submission"
    assert_not_includes response.body, "@customer"

    # Customer dashboard displays escaped value
    sign_in_as(@user_a)
    get survey_submission_path(survey, survey.submissions.last)
    assert_response :success
    # Raw unescaped script tag should NOT be executed
    assert_includes response.body, "&lt;script&gt;alert(&#39;pwned&#39;)&lt;/script&gt;"
  end
end
