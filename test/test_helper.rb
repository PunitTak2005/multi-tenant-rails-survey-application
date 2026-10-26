ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Disable parallelization for stable local database testing
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all

    def sign_in_as(user, password: "ChangeMe123!")
      post login_path, params: { email: user.email, password: password }
    end
  end
end
