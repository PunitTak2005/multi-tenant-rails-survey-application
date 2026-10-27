# frozen_string_literal: true

require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(name: "Acme Corp")
    @user = @customer.users.create!(
      name: "Admin User",
      email: "admin@acme.test",
      password: "ChangeMe123!"
    )
  end

  # --- 1. Login Page Tests ---

  test "login page is accessible and renders email, password fields, and submit button" do
    get login_path
    assert_response :success
    assert_select "form[action='/login'][method='post']"
    assert_select "input[name='email'][type='email']"
    assert_select "input[name='password'][type='password']"
    assert_select "input[type='submit'][value='Log in']"
  end

  test "login form includes CSRF authenticity token when forgery protection is enabled" do
    ActionController::Base.allow_forgery_protection = true
    get login_path
    assert_response :success
    assert_select "input[name='authenticity_token']"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # --- 2. Valid Login Tests ---

  test "successful login redirects to dashboard and establishes authenticated session" do
    get login_path
    assert_response :success

    post login_path, params: { email: @user.email, password: "ChangeMe123!" }
    assert_redirected_to dashboard_path
    assert_equal @user.id, session[:user_id]

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Acme Corp Dashboard/
    assert_includes response.body, "admin@acme.test"
  end

  # --- 3. Invalid Login Tests (Cases A through E) ---

  test "case A: wrong password denies login with generic alert" do
    post login_path, params: { email: @user.email, password: "wrong-password" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_includes response.body, "Invalid email or password."
  end

  test "case B: unknown email denies login with generic alert without leaking account existence" do
    post login_path, params: { email: "nonexistent@acme.test", password: "ChangeMe123!" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_includes response.body, "Invalid email or password."
  end

  test "case C: blank email denies login" do
    post login_path, params: { email: "", password: "ChangeMe123!" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_includes response.body, "Invalid email or password."
  end

  test "case D: blank password denies login" do
    post login_path, params: { email: @user.email, password: "" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_includes response.body, "Invalid email or password."
  end

  test "case E: both email and password blank denies login" do
    post login_path, params: { email: "", password: "" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_includes response.body, "Invalid email or password."
  end

  # --- 4. Authenticated State Tests ---

  test "authenticated user can access all protected tenant pages" do
    post login_path, params: { email: @user.email, password: "ChangeMe123!" }
    assert_redirected_to dashboard_path

    # Dashboard
    get dashboard_path
    assert_response :success

    # Surveys List
    get surveys_path
    assert_response :success

    # New Survey Form
    get new_survey_path
    assert_response :success

    # Analytics Page
    get analytics_path
    assert_response :success
  end

  # --- 5. Logout & Session Invalidation Tests ---

  test "logout clears session and blocks subsequent access to protected pages" do
    # Log in
    post login_path, params: { email: @user.email, password: "ChangeMe123!" }
    assert_equal @user.id, session[:user_id]

    get dashboard_path
    assert_response :success

    # Log out
    delete logout_path
    assert_redirected_to login_path
    assert_nil session[:user_id]

    # Attempt to access protected pages after logout
    get dashboard_path
    assert_redirected_to login_path

    get surveys_path
    assert_redirected_to login_path

    get new_survey_path
    assert_redirected_to login_path
  end

  # --- 6. Unauthenticated Survey Creation Flow & Database Verification ---

  test "unauthenticated user cannot reach new survey form or create survey in database" do
    # GET new survey form is blocked
    get new_survey_path
    assert_redirected_to login_path
    assert_equal "You must log in to access this page.", flash[:alert]

    # POST create survey is blocked and database count does not increase
    assert_no_difference -> { Survey.count } do
      post surveys_path, params: {
        survey: {
          title: "Unauthorized Survey",
          description: "This should not be saved",
          questions_attributes: {
            "0" => { question_text: "Q1", question_type: "text", position: 1 }
          }
        }
      }
    end

    assert_redirected_to login_path
    assert_equal "You must log in to access this page.", flash[:alert]
    assert_nil Survey.find_by(title: "Unauthorized Survey")
  end

  # --- 7. Unauthenticated Survey Management Endpoints ---

  test "unauthenticated requests to edit, update, delete, and publish are strictly rejected" do
    survey = @customer.surveys.create!(title: "Original Survey", status: :draft)
    survey.questions.create!(question_text: "Q1", question_type: :text, position: 1)

    # Edit
    get edit_survey_path(survey)
    assert_redirected_to login_path

    # Update
    patch survey_path(survey), params: { survey: { title: "Hacked Survey Title" } }
    assert_redirected_to login_path
    assert_equal "Original Survey", survey.reload.title

    # Delete
    assert_no_difference -> { Survey.count } do
      delete survey_path(survey)
    end
    assert_redirected_to login_path

    # Publish
    post publish_survey_path(survey)
    assert_redirected_to login_path
    assert survey.reload.draft?
  end

  # --- 8. Session Manipulation & Impersonation Attempts ---

  test "query parameter manipulation cannot bypass authentication or spoof identity" do
    # Malicious attempt to inject user_id or customer_id via URL params
    get dashboard_path, params: { user_id: @user.id, customer_id: @customer.id }
    assert_redirected_to login_path
    assert_nil session[:user_id]

    # Malicious POST attempt injecting user_id/customer_id params without session
    assert_no_difference -> { Survey.count } do
      post surveys_path, params: {
        user_id: @user.id,
        customer_id: @customer.id,
        survey: { title: "Spoofed Survey" }
      }
    end
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  # --- 9. Authenticated Survey Creation Flow ---

  test "authenticated user can successfully create survey assigned to their customer" do
    sign_in_as(@user, password: "ChangeMe123!")

    get new_survey_path
    assert_response :success

    assert_difference -> { @customer.surveys.count }, 1 do
      post surveys_path, params: {
        survey: {
          title: "Legitimate CSAT Survey",
          description: "Quarterly review",
          questions_attributes: {
            "0" => { question_text: "How was your experience?", question_type: "text", position: 1 }
          }
        }
      }
    end

    survey = @customer.surveys.find_by(title: "Legitimate CSAT Survey")
    assert_not_nil survey
    assert_equal @customer.id, survey.customer_id
    assert_redirected_to survey_path(survey)
  end
end
