require "test_helper"

class SurveyCrudTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(name: "Acme Corporation")
    @user = @customer.users.create!(
      name: "Acme Admin",
      email: "admin@acme.test",
      password: "ChangeMe123!"
    )
    sign_in_as(@user)
  end

  test "create survey with nested questions and options" do
    get new_survey_path
    assert_response :success

    survey_params = {
      survey: {
        title: "Customer Satisfaction Survey",
        description: "Standard quarterly feedback survey",
        questions_attributes: {
          "0" => {
            question_text: "How satisfied are you?",
            question_type: "multiple_choice",
            position: 1,
            required: "1",
            question_options_attributes: {
              "0" => { label: "Very satisfied", position: 1 },
              "1" => { label: "Unsatisfied", position: 2 }
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

    assert_difference -> { @customer.surveys.count } => 1, -> { Question.count } => 3, -> { QuestionOption.count } => 2 do
      post surveys_path, params: survey_params
    end

    survey = @customer.surveys.last
    assert_redirected_to survey_path(survey)
    assert_equal "Customer Satisfaction Survey", survey.title
    assert survey.draft?
  end

  test "edit survey updates attributes" do
    survey = @customer.surveys.create!(title: "Old Title")

    patch survey_path(survey), params: { survey: { title: "Updated Title" } }
    assert_redirected_to survey_path(survey)
    survey.reload
    assert_equal "Updated Title", survey.title
  end

  test "delete survey removes record" do
    survey = @customer.surveys.create!(title: "To Be Deleted")

    assert_difference -> { @customer.surveys.count } => -1 do
      delete survey_path(survey)
    end
    assert_redirected_to surveys_path
  end

  test "publish survey transition" do
    survey = @customer.surveys.create!(title: "Survey To Publish")
    q = survey.questions.create!(question_text: "Favorite feature?", question_type: :text, position: 1)

    post publish_survey_path(survey)
    assert_redirected_to survey_path(survey)
    survey.reload
    assert survey.published?
    assert_not_nil survey.published_at
  end

  test "cannot publish empty survey" do
    empty_survey = @customer.surveys.create!(title: "Empty Survey")

    post publish_survey_path(empty_survey)
    assert_redirected_to survey_path(empty_survey)
    empty_survey.reload
    assert empty_survey.draft?
    assert_includes flash[:alert], "Survey must have at least one question"
  end
end
