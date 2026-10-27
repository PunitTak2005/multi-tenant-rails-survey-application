# frozen_string_literal: true

require "test_helper"

class Requirement1SurveyArchitectureTest < ActionDispatch::IntegrationTest
  setup do
    @customer_a = Customer.create!(name: "Acme Enterprises")
    @customer_b = Customer.create!(name: "Globex Global")

    @user_a = @customer_a.users.create!(
      name: "Alice Acme",
      email: "alice@acme.test",
      password: "ChangeMe123!"
    )
    @user_b = @customer_b.users.create!(
      name: "Bob Globex",
      email: "bob@globex.test",
      password: "ChangeMe123!"
    )
  end

  # --- 1. Five-Question Survey Creation Test (Section 8) ---
  test "authenticated user creates a 5-question survey with text, number, and multiple choice" do
    sign_in_as(@user_a)

    survey_params = {
      survey: {
        title: "Developer Background Survey",
        description: "Collecting developer experience and language preferences",
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
            question_text: "Which language do you prefer?",
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
            question_text: "Tell us about your experience.",
            question_type: "text",
            position: 4,
            required: "0"
          },
          "4" => {
            question_text: "How many projects have you completed?",
            question_type: "number",
            position: 5,
            required: "0"
          }
        }
      }
    }

    assert_difference -> { @customer_a.surveys.count } => 1,
                      -> { Question.count } => 5,
                      -> { QuestionOption.count } => 4 do
      post surveys_path, params: survey_params
    end

    survey = @customer_a.surveys.find_by(title: "Developer Background Survey")
    assert_not_nil survey
    assert_redirected_to survey_path(survey)
    assert survey.draft?
    assert_equal 5, survey.questions.count

    # Check question ordering
    positions = survey.questions.reload.map(&:position)
    assert_equal [ 1, 2, 3, 4, 5 ], positions

    # Check multiple-choice options
    mc_q = survey.questions.find_by(question_type: :multiple_choice)
    assert_equal 4, mc_q.question_options.count
    assert_equal %w[Ruby JavaScript Python Java], mc_q.question_options.order(:position).pluck(:label)
  end

  # --- 2. Six-Question Mixed Pattern & Deterministic Ordering (Section 10) ---
  test "survey supports 6 questions with alternating types and deterministic ordering" do
    sign_in_as(@user_a)

    survey = @customer_a.surveys.create!(title: "6-Question Mixed Survey", status: :draft)
    q1 = survey.questions.create!(question_text: "Text 1", question_type: :text, position: 1)
    q2 = survey.questions.create!(question_text: "Number 1", question_type: :number, position: 2)
    q3 = survey.questions.create!(question_text: "MC 1", question_type: :multiple_choice, position: 3)
    q3.question_options.create!(label: "Opt A", position: 1)
    q4 = survey.questions.create!(question_text: "Text 2", question_type: :text, position: 4)
    q5 = survey.questions.create!(question_text: "Number 2", question_type: :number, position: 5)
    q6 = survey.questions.create!(question_text: "MC 2", question_type: :multiple_choice, position: 6)
    q6.question_options.create!(label: "Opt B", position: 1)

    # Verify all belong to same survey and customer
    assert_equal 6, survey.questions.count
    assert_equal [ 1, 2, 3, 4, 5, 6 ], survey.questions.order(:position).pluck(:position)
    assert_equal %w[text number multiple_choice text number multiple_choice],
                 survey.questions.order(:position).pluck(:question_type)
  end

  # --- 3. Publishing & Public Token Security (Sections 13-17) ---
  test "draft survey is protected and becomes public only after publishing" do
    survey = @customer_a.surveys.create!(title: "Launch Feedback", status: :draft)
    survey.questions.create!(question_text: "Initial thoughts?", question_type: :text, position: 1)

    # 1. Draft survey returns 404 to unauthenticated public requests
    get public_survey_path(survey.public_token)
    assert_response :not_found

    # 2. Authenticate and publish survey
    sign_in_as(@user_a)
    post publish_survey_path(survey)
    assert_redirected_to survey_path(survey)

    survey.reload
    assert survey.published?
    assert_not_nil survey.published_at
    assert_not_nil survey.public_token
    assert survey.public_token.length >= 20, "Public token must have sufficient entropy"

    # 3. Log out and access via public URL
    delete logout_path

    get public_survey_path(survey.public_token)
    assert_response :success
    assert_includes response.body, "Launch Feedback"
    assert_includes response.body, "Initial thoughts?"
  end

  # --- 4. Anonymous Submission & Typed Answer Persistence (Sections 18-21) ---
  test "anonymous user can submit valid typed answers stored in normalized schema" do
    survey = @customer_a.surveys.create!(title: "CSAT 2026", status: :published, published_at: Time.current)
    q_txt = survey.questions.create!(question_text: "Name", question_type: :text, position: 1, required: true)
    q_num = survey.questions.create!(question_text: "Rating", question_type: :number, position: 2, required: true)
    q_mc = survey.questions.create!(question_text: "Tier", question_type: :multiple_choice, position: 3, required: true)
    opt_pro = q_mc.question_options.create!(label: "Enterprise", position: 1)

    answers = {
      q_txt.id.to_s => "Grace Hopper",
      q_num.id.to_s => "10.0",
      q_mc.id.to_s => opt_pro.id.to_s
    }

    assert_difference -> { survey.submissions.count } => 1, -> { Answer.count } => 3 do
      post submit_public_survey_path(survey.public_token), params: { answers: answers }
    end

    assert_redirected_to public_survey_success_path(survey.public_token)

    submission = survey.submissions.last
    assert_not_nil submission.submitted_at

    ans_txt = submission.answers.find_by(question: q_txt)
    ans_num = submission.answers.find_by(question: q_num)
    ans_mc = submission.answers.find_by(question: q_mc)

    assert_equal "Grace Hopper", ans_txt.text_value
    assert_nil ans_txt.number_value
    assert_nil ans_txt.selected_option_id

    assert_equal BigDecimal("10.0"), ans_num.number_value
    assert_nil ans_num.text_value

    assert_equal opt_pro.id, ans_mc.selected_option_id
    assert_equal "Enterprise", ans_mc.selected_option.label
  end

  # --- 5. Multiple Submissions Retention (Section 22) ---
  test "multiple submissions to the same published survey are independently retained" do
    survey = @customer_a.surveys.create!(title: "Poll", status: :published, published_at: Time.current)
    q = survey.questions.create!(question_text: "Feedback", question_type: :text, position: 1)

    3.times do |i|
      post submit_public_survey_path(survey.public_token), params: { answers: { q.id.to_s => "Response #{i + 1}" } }
      assert_redirected_to public_survey_success_path(survey.public_token)
    end

    assert_equal 3, survey.submissions.count
    stored_texts = survey.answers.where(question: q).pluck(:text_value)
    assert_equal [ "Response 1", "Response 2", "Response 3" ], stored_texts
  end

  # --- 6. Cross-Question & Cross-Survey Option Hijacking (Section 20) ---
  test "rejects submission when option ID belongs to a question from another survey" do
    survey_a = @customer_a.surveys.create!(title: "Survey A", status: :published, published_at: Time.current)
    q_a = survey_a.questions.create!(question_text: "Choice A", question_type: :multiple_choice, position: 1)
    q_a.question_options.create!(label: "Opt A", position: 1)

    survey_b = @customer_b.surveys.create!(title: "Survey B", status: :published, published_at: Time.current)
    q_b = survey_b.questions.create!(question_text: "Choice B", question_type: :multiple_choice, position: 1)
    opt_b = q_b.question_options.create!(label: "Alien Opt B", position: 1)

    # Malicious attempt: Submit Survey A with Option ID from Survey B
    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      post submit_public_survey_path(survey_a.public_token), params: {
        answers: { q_a.id.to_s => opt_b.id.to_s }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "invalid"
  end

  # --- 7. Customer Tenant Ownership Boundaries (Section 23) ---
  test "customer tenant ownership boundaries are enforced across all survey operations" do
    survey_b = @customer_b.surveys.create!(title: "Secret Globex Survey", status: :published)
    survey_b.questions.create!(question_text: "Internal Metric", question_type: :number, position: 1)

    sign_in_as(@user_a)

    # 1. Cannot view Survey B in index
    get surveys_path
    assert_response :success
    assert_not_includes response.body, "Secret Globex Survey"

    # 2. Cannot view Survey B by ID
    get survey_path(survey_b)
    assert_redirected_to surveys_path

    # 3. Cannot edit Survey B
    get edit_survey_path(survey_b)
    assert_redirected_to surveys_path

    # 4. Cannot update Survey B
    patch survey_path(survey_b), params: { survey: { title: "Hijacked" } }
    assert_redirected_to surveys_path
    assert_equal "Secret Globex Survey", survey_b.reload.title

    # 5. Cannot delete Survey B
    assert_no_difference -> { Survey.count } do
      delete survey_path(survey_b)
    end
    assert_redirected_to surveys_path
    assert Survey.exists?(survey_b.id)
  end

  # --- 8. XSS Prevention & Safe Escaping (Section 29) ---
  test "HTML and script injection payloads are safely escaped in survey views" do
    sign_in_as(@user_a)

    xss_payload = "<script>alert('XSS')</script>"
    survey = @customer_a.surveys.create!(
      title: "Security Check #{xss_payload}",
      description: "Desc #{xss_payload}",
      status: :published,
      published_at: Time.current
    )
    survey.questions.create!(
      question_text: "Question #{xss_payload}",
      question_type: :text,
      position: 1
    )

    # Public survey view
    get public_survey_path(survey.public_token)
    assert_response :success
    refute_includes response.body, "<script>alert('XSS')</script>"
    assert_includes response.body, "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
  end
end
