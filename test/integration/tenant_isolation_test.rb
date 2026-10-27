require "test_helper"

class TenantIsolationTest < ActionDispatch::IntegrationTest
  setup do
    # Customer A
    @customer_a = Customer.create!(name: "Customer Alpha")
    @user_a = @customer_a.users.create!(
      name: "Alpha Admin",
      email: "alpha@example.com",
      password: "ChangeMe123!"
    )
    @survey_a = @customer_a.surveys.create!(
      title: "Alpha Secret Survey",
      status: :published,
      published_at: Time.current
    )
    @sub_a = @survey_a.submissions.create!(submitted_at: Time.current)

    # Customer B
    @customer_b = Customer.create!(name: "Customer Beta")
    @user_b = @customer_b.users.create!(
      name: "Beta Admin",
      email: "beta@example.com",
      password: "ChangeMe123!"
    )
    @survey_b = @customer_b.surveys.create!(
      title: "Beta Secret Survey",
      status: :published,
      published_at: Time.current
    )
    @sub_b = @survey_b.submissions.create!(submitted_at: Time.current)
  end

  test "Customer A cannot view Customer B's surveys list" do
    sign_in_as(@user_a)
    get surveys_path
    assert_response :success
    assert_includes response.body, "Alpha Secret Survey"
    assert_not_includes response.body, "Beta Secret Survey"
  end

  test "Customer A cannot view Customer B's survey details by ID" do
    sign_in_as(@user_a)
    get survey_path(@survey_b)
    # Scoped query fails, redirects with alert
    assert_redirected_to surveys_path
    follow_redirect!
    assert_includes flash[:alert], "Survey not found"
  end

  test "Customer A cannot edit Customer B's survey" do
    sign_in_as(@user_a)
    get edit_survey_path(@survey_b)
    assert_redirected_to surveys_path
    assert_includes flash[:alert], "Survey not found"
  end

  test "Customer A cannot update Customer B's survey" do
    sign_in_as(@user_a)
    patch survey_path(@survey_b), params: { survey: { title: "Hacked Title" } }
    assert_redirected_to surveys_path
    @survey_b.reload
    assert_equal "Beta Secret Survey", @survey_b.title
  end

  test "Customer A cannot delete Customer B's survey" do
    sign_in_as(@user_a)
    assert_no_difference -> { Survey.count } do
      delete survey_path(@survey_b)
    end
    assert_redirected_to surveys_path
    assert Survey.exists?(@survey_b.id)
  end

  test "Customer A cannot view Customer B's submissions index" do
    sign_in_as(@user_a)
    get survey_submissions_path(@survey_b)
    assert_redirected_to surveys_path
    assert_includes flash[:alert], "Survey not found"
  end

  test "Customer A cannot view Customer B's individual submission details" do
    sign_in_as(@user_a)
    get survey_submission_path(@survey_b, @sub_b)
    assert_redirected_to surveys_path
    assert_includes flash[:alert], "Survey not found"
  end

  test "Customer A analytics only aggregates Customer A responses" do
    sign_in_as(@user_a)
    get analytics_path
    assert_response :success
    # Should only report Alpha's submissions (1), never Beta's
    assert_select ".stat-value", text: "1"
    assert_includes response.body, "Alpha Secret Survey"
    assert_not_includes response.body, "Beta Secret Survey"
  end

  test "reverse isolation: Customer B cannot access Customer A data" do
    sign_in_as(@user_b)

    get survey_path(@survey_a)
    assert_redirected_to surveys_path
    assert_includes flash[:alert], "Survey not found"

    get survey_submissions_path(@survey_a)
    assert_redirected_to surveys_path

    get analytics_path
    assert_response :success
    assert_includes response.body, "Beta Secret Survey"
    assert_not_includes response.body, "Alpha Secret Survey"
  end

  test "ownership parameter tampering: customer_id cannot be mass-assigned to create resource for another customer" do
    sign_in_as(@user_a)

    assert_difference -> { @customer_a.surveys.count }, 1 do
      assert_no_difference -> { @customer_b.surveys.count } do
        post surveys_path, params: {
          survey: {
            title: "Tampered Survey",
            customer_id: @customer_b.id,
            questions_attributes: {
              "0" => { question_text: "Q?", question_type: "text", position: 1 }
            }
          }
        }
      end
    end

    created_survey = Survey.find_by(title: "Tampered Survey")
    assert_equal @customer_a.id, created_survey.customer_id
    refute_equal @customer_b.id, created_survey.customer_id
  end
end
