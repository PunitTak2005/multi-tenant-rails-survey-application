# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--headless=new")
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
    driver_option.add_argument("--disable-gpu")
  end

  def sign_in_as(user, password: "ChangeMe123!")
    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: password
    click_button "Log in"
    assert_current_path dashboard_path
    assert_text "Welcome back"
  end
end
