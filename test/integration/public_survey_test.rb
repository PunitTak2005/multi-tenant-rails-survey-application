require "test_helper"

class PublicSurveyTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(name: "Acme Corporation")
    @published_survey = @customer.surveys.create!(
      title: "Public Feedback Survey",
      description: "Please share your experience.",
      status: :published,
      published_at: Time.current
    )

    @q1 = @published_survey.questions.create!(
      question_text: "How satisfied are you?",
      question_type: :multiple_choice,
      position: 1,
      required: true
    )
    @opt_sat = @q1.question_options.create!(label: "Satisfied", position: 1)
    @opt_unsat = @q1.question_options.create!(label: "Unsatisfied", position: 2)

    @q2 = @published_survey.questions.create!(
      question_text: "Feedback text",
      question_type: :text,
      position: 2,
      required: false
    )

    @q3 = @published_survey.questions.create!(
      question_text: "Usage count",
      question_type: :number,
      position: 3,
      required: true
    )

    @draft_survey = @customer.surveys.create!(
      title: "Draft Survey",
      status: :draft
    )
  end

  test "published survey is publicly accessible without login" do
    get public_survey_path(@published_survey.public_token)
    assert_response :success
    assert_includes response.body, "Public Feedback Survey"
    assert_includes response.body, "Please share your experience."
    assert_includes response.body, "How satisfied are you?"
    assert_includes response.body, "Satisfied"
  end

  test "draft survey is not publicly accessible" do
    get public_survey_path(@draft_survey.public_token)
    assert_response :not_found
  end

  test "invalid public token returns 404" do
    get public_survey_path("nonexistent-token-12345")
    assert_response :not_found
  end

  test "public respondent submits valid survey response" do
    answers_params = {
      @q1.id.to_s => @opt_sat.id.to_s,
      @q2.id.to_s => "Everything worked like a charm!",
      @q3.id.to_s => "5"
    }

    assert_difference -> { @published_survey.submissions.count } => 1, -> { Answer.count } => 3 do
      post submit_public_survey_path(@published_survey.public_token), params: { answers: answers_params }
    end

    assert_redirected_to public_survey_success_path(@published_survey.public_token)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Thank you!"
    assert_includes response.body, "Your survey response has been submitted successfully."
  end

  test "submission rejects missing required fields and shows errors" do
    answers_params = {
      @q2.id.to_s => "Only feedback text"
      # missing required q1 and q3
    }

    assert_no_difference -> { @published_survey.submissions.count } do
      post submit_public_survey_path(@published_survey.public_token), params: { answers: answers_params }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "required"
  end

  test "submission rejects invalid option for multiple choice question" do
    answers_params = {
      @q1.id.to_s => "999999", # Invalid option ID
      @q3.id.to_s => "3"
    }

    assert_no_difference -> { @published_survey.submissions.count } do
      post submit_public_survey_path(@published_survey.public_token), params: { answers: answers_params }
    end

    assert_response :unprocessable_entity
  end
end
