require "test_helper"

class AcceptanceTest < ActionDispatch::IntegrationTest
  test "section 42: full manual acceptance test workflow" do
    # Customer A
    customer_a = Customer.create!(name: "Acme Corporation")
    user_a = customer_a.users.create!(
      name: "Acme Admin",
      email: "admin@acme.test",
      password: "ChangeMe123!"
    )

    # 1. Log in as Customer A
    post login_path, params: { email: "admin@acme.test", password: "ChangeMe123!" }
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success

    # 2. Create Survey: Customer Satisfaction Survey with the 3 questions
    survey_payload = {
      survey: {
        title: "Customer Satisfaction Survey",
        description: "Official customer satisfaction survey",
        questions_attributes: {
          "0" => {
            question_text: "How satisfied are you?",
            question_type: "multiple_choice",
            position: 1,
            required: "1",
            question_options_attributes: {
              "0" => { label: "Very satisfied", position: 1 },
              "1" => { label: "Satisfied", position: 2 },
              "2" => { label: "Neutral", position: 3 },
              "3" => { label: "Unsatisfied", position: 4 }
            }
          },
          "1" => {
            question_text: "Tell us what we can improve.",
            question_type: "text",
            position: 2,
            required: "0"
          },
          "2" => {
            question_text: "How many times have you used our service?",
            question_type: "number",
            position: 3,
            required: "1"
          }
        }
      }
    }

    assert_difference -> { customer_a.surveys.count } => 1 do
      post surveys_path, params: survey_payload
    end

    survey = customer_a.surveys.order(:created_at).last
    assert_equal "Customer Satisfaction Survey", survey.title
    assert survey.draft?
    assert_equal 3, survey.questions.count

    # 3. Publish the survey
    post publish_survey_path(survey)
    assert_redirected_to survey_path(survey)
    survey.reload
    assert survey.published?
    assert_not_nil survey.published_at
    public_token = survey.public_token

    # 4. Open public URL in a logged-out session
    delete logout_path
    assert_nil session[:user_id]

    get public_survey_path(public_token)
    assert_response :success
    assert_includes response.body, "Customer Satisfaction Survey"
    assert_includes response.body, "How satisfied are you?"
    assert_includes response.body, "Tell us what we can improve."
    assert_includes response.body, "How many times have you used our service?"
    assert_includes response.body, "Very satisfied"
    assert_includes response.body, "Satisfied"
    assert_includes response.body, "Neutral"
    assert_includes response.body, "Unsatisfied"

    # 5. Submit response
    q_mc = survey.questions.find_by(question_type: :multiple_choice)
    q_text = survey.questions.find_by(question_type: :text)
    q_num = survey.questions.find_by(question_type: :number)
    opt_very_sat = q_mc.question_options.find_by(label: "Very satisfied")

    answers_data = {
      q_mc.id.to_s => opt_very_sat.id.to_s,
      q_text.id.to_s => "Fast performance and great user experience.",
      q_num.id.to_s => "12"
    }

    assert_difference -> { survey.submissions.count } => 1, -> { Answer.count } => 3 do
      post submit_public_survey_path(public_token), params: { answers: answers_data }
    end

    assert_redirected_to public_survey_success_path(public_token)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Thank you!"
    assert_includes response.body, "Your survey response has been submitted successfully."

    # 6. Log back in as Customer A
    post login_path, params: { email: "admin@acme.test", password: "ChangeMe123!" }
    assert_redirected_to dashboard_path
    follow_redirect!

    # 7. Confirm the submission appears in Submissions view
    get survey_submissions_path(survey)
    assert_response :success
    assert_includes response.body, "3 answers"
    submission = survey.submissions.last
    assert_includes response.body, "##{submission.id}"

    # 8. View submission detail page
    get survey_submission_path(survey, submission)
    assert_response :success
    assert_includes response.body, "Very satisfied"
    assert_includes response.body, "Fast performance and great user experience."
    assert_includes response.body, "12"

    # 9. Confirm analytics shows the response
    get analytics_path
    assert_response :success
    today_str = Date.current.strftime("%Y-%m-%d")
    assert_includes response.body, today_str
  end

  test "section 43: mandatory tenant isolation acceptance test" do
    # Customer A
    cust_a = Customer.create!(name: "Acme Corporation")
    user_a = cust_a.users.create!(name: "Admin A", email: "admin_a@acme.test", password: "ChangeMe123!")
    survey_a = cust_a.surveys.create!(title: "Survey Alpha", status: :published, published_at: Time.current)
    sub_a = survey_a.submissions.create!(submitted_at: Time.current)

    # Customer B
    cust_b = Customer.create!(name: "Beta Technologies")
    user_b = cust_b.users.create!(name: "Admin B", email: "admin_b@beta.test", password: "ChangeMe123!")
    survey_b = cust_b.surveys.create!(title: "Survey Beta", status: :published, published_at: Time.current)
    sub_b = survey_b.submissions.create!(submitted_at: Time.current)

    # Log in as Customer A
    post login_path, params: { email: user_a.email, password: "ChangeMe123!" }
    assert_redirected_to dashboard_path

    # Attempt to access Customer B's survey
    get survey_path(survey_b)
    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found"

    # Attempt to access Customer B's submissions index
    get survey_submissions_path(survey_b)
    assert_redirected_to surveys_path

    # Attempt to access Customer B's submission show
    get survey_submission_path(survey_b, sub_b)
    assert_redirected_to surveys_path

    # Check Customer A's analytics - must NOT show Customer B's surveys or submissions
    get analytics_path
    assert_response :success
    assert_includes response.body, "Survey Alpha"
    assert_not_includes response.body, "Survey Beta"

    # REPEAT IN REVERSE: Log in as Customer B
    post login_path, params: { email: user_b.email, password: "ChangeMe123!" }
    assert_redirected_to dashboard_path

    get survey_path(survey_a)
    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found"

    get survey_submissions_path(survey_a)
    assert_redirected_to surveys_path

    get survey_submission_path(survey_a, sub_a)
    assert_redirected_to surveys_path

    get analytics_path
    assert_response :success
    assert_includes response.body, "Survey Beta"
    assert_not_includes response.body, "Survey Alpha"
  end
end
