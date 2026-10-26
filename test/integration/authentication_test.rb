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

  test "unauthenticated user is redirected to login" do
    get dashboard_path
    assert_redirected_to login_path
    follow_redirect!
    assert_select "h1", "Welcome Back"
  end

  test "successful login redirects to dashboard" do
    get login_path
    assert_response :success

    post login_path, params: { email: @user.email, password: "ChangeMe123!" }
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Acme Corp Dashboard/
    assert_equal @user.id, session[:user_id]
  end

  test "invalid login fails with alert" do
    post login_path, params: { email: @user.email, password: "wrong-password" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "logout clears session and redirects to login" do
    post login_path, params: { email: @user.email, password: "ChangeMe123!" }
    assert_equal @user.id, session[:user_id]

    delete logout_path
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end
end
