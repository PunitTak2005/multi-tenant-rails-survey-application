# frozen_string_literal: true

require "test_helper"

class CaptchaVerifierTest < ActiveSupport::TestCase
  setup do
    CaptchaVerifier.mock_result = nil
    CaptchaVerifier.request_handler = nil
  end

  teardown do
    CaptchaVerifier.mock_result = nil
    CaptchaVerifier.request_handler = nil
  end
  test "enabled? is false by default when secret key is unset" do
    assert_not CaptchaVerifier.enabled?
  end

  test "site_key returns default dummy or env value" do
    assert_equal "1x00000000000000000000AA", CaptchaVerifier.site_key
  end

  test "verify returns success when CAPTCHA is disabled" do
    result = CaptchaVerifier.verify(nil)
    assert_predicate result, :success?
  end

  test "verify rejects blank token when CAPTCHA is enforced" do
    CaptchaVerifier.with_enforced do
      result = CaptchaVerifier.verify("")
      assert_not result.success?
      assert_equal "Please complete the CAPTCHA challenge.", result.error_message
    end
  end

  test "with_mock allows mocking successful verification" do
    CaptchaVerifier.with_mock(success: true) do
      assert_predicate CaptchaVerifier.verify("any-token"), :success?
    end
  end

  test "with_mock allows mocking failed verification with custom message" do
    CaptchaVerifier.with_mock(success: false, error_message: "Bot detected.") do
      result = CaptchaVerifier.verify("any-token")
      assert_not result.success?
      assert_equal "Bot detected.", result.error_message
    end
  end

  test "parse_response handles Cloudflare success payload" do
    fake_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    fake_response.instance_variable_set(:@read, true)
    fake_response.define_singleton_method(:body) { '{"success": true}' }

    result = CaptchaVerifier.send(:parse_response, fake_response)
    assert_predicate result, :success?
  end

  test "parse_response handles expired token error code" do
    fake_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    fake_response.instance_variable_set(:@read, true)
    fake_response.define_singleton_method(:body) { '{"success": false, "error-codes": ["timeout-or-duplicate"]}' }

    result = CaptchaVerifier.send(:parse_response, fake_response)
    assert_not result.success?
    assert_equal "CAPTCHA challenge expired. Please verify again.", result.error_message
  end

  test "parse_response handles generic Cloudflare failure" do
    fake_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    fake_response.instance_variable_set(:@read, true)
    fake_response.define_singleton_method(:body) { '{"success": false, "error-codes": ["invalid-input-response"]}' }

    result = CaptchaVerifier.send(:parse_response, fake_response)
    assert_not result.success?
    assert_equal "We couldn't verify that you're human. Please try again.", result.error_message
  end

  test "parse_response handles provider 500 error safely" do
    fake_response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
    result = CaptchaVerifier.send(:parse_response, fake_response)
    assert_not result.success?
    assert_equal "We couldn't verify that you're human. Please try again.", result.error_message
  end

  test "verify rescues network exceptions and fails closed" do
    CaptchaVerifier.with_enforced do
      old_secret = ENV["TURNSTILE_SECRET_KEY"]
      ENV["TURNSTILE_SECRET_KEY"] = "dummy-secret"
      CaptchaVerifier.request_handler = ->(*) { raise Net::ReadTimeout, "Execution expired" }

      result = CaptchaVerifier.verify("token-123")
      assert_not result.success?
      assert_equal "We couldn't verify that you're human. Please try again.", result.error_message
    ensure
      ENV["TURNSTILE_SECRET_KEY"] = old_secret
      CaptchaVerifier.request_handler = nil
    end
  end
end
