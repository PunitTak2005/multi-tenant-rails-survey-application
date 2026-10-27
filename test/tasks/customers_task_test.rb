# frozen_string_literal: true

require "test_helper"
require "rake"

class CustomersTaskTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("customers:setup")
  end

  test "customers:setup provisions both customer tenants and users idempotently" do
    # Run the setup task
    Rake::Task["customers:setup"].reenable
    Rake::Task["customers:setup"].invoke

    # Verify Customer A and User A
    customer_a = Customer.find_by(name: "Acme Corporation")
    assert_not_nil customer_a
    user_a = User.find_by(email: "admin@acme.test")
    assert_not_nil user_a
    assert_equal customer_a.id, user_a.customer_id
    assert user_a.authenticate("ChangeMe123!"), "User A should authenticate with ChangeMe123!"

    # Verify Customer B and User B
    customer_b = Customer.find_by(name: "Beta Technologies")
    assert_not_nil customer_b
    user_b = User.find_by(email: "beta@beta.test")
    assert_not_nil user_b
    assert_equal customer_b.id, user_b.customer_id
    assert user_b.authenticate("ChangeMe123!"), "User B should authenticate with ChangeMe123!"

    # Test login workflow with User A
    post login_path, params: { email: "admin@acme.test", password: "ChangeMe123!" }
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Acme Corporation"

    # Test re-running task is strictly idempotent
    customer_count_before = Customer.count
    user_count_before = User.count

    Rake::Task["customers:setup"].reenable
    Rake::Task["customers:setup"].invoke

    assert_equal customer_count_before, Customer.count, "Must not create duplicate customers"
    assert_equal user_count_before, User.count, "Must not create duplicate users"
  end

  test "customers:create_initial supports environment variables and idempotent updates" do
    ENV["INITIAL_CUSTOMER_NAME"] = "Custom Corp"
    ENV["INITIAL_USER_NAME"] = "Custom Admin"
    ENV["INITIAL_USER_EMAIL"] = "custom_admin@custom.test"
    ENV["INITIAL_USER_PASSWORD"] = "SecretPass123!"

    Rake::Task["customers:create_initial"].reenable
    Rake::Task["customers:create_initial"].invoke

    customer = Customer.find_by(name: "Custom Corp")
    assert_not_nil customer
    user = User.find_by(email: "custom_admin@custom.test")
    assert_not_nil user
    assert_equal customer.id, user.customer_id
    assert user.authenticate("SecretPass123!")

    # Verify login
    post login_path, params: { email: "custom_admin@custom.test", password: "SecretPass123!" }
    assert_redirected_to dashboard_path

    # Clean up environment variables
    ENV.delete("INITIAL_CUSTOMER_NAME")
    ENV.delete("INITIAL_USER_NAME")
    ENV.delete("INITIAL_USER_EMAIL")
    ENV.delete("INITIAL_USER_PASSWORD")
  end
end
