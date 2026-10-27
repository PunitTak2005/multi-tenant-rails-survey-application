# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class CaptchaVerifier
  VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  Result = Struct.new(:success?, :error_message, keyword_init: true)

  class << self
    attr_accessor :mock_result, :request_handler

    def enabled?
      return true if mock_result.present?
      return true if Thread.current[:captcha_enforced] == true

      ENV["TURNSTILE_SECRET_KEY"].present?
    end

    def site_key
      ENV.fetch("TURNSTILE_SITE_KEY", "1x00000000000000000000AA")
    end

    def secret_key
      ENV["TURNSTILE_SECRET_KEY"]
    end

    def with_mock(success:, error_message: nil)
      old_mock = mock_result
      self.mock_result = Result.new(success?: success, error_message: error_message)
      yield
    ensure
      self.mock_result = old_mock
    end

    def with_enforced(enforced = true)
      old_val = Thread.current[:captcha_enforced]
      Thread.current[:captcha_enforced] = enforced
      yield
    ensure
      Thread.current[:captcha_enforced] = old_val
    end

    def verify(token, remote_ip: nil)
      return mock_result if mock_result.present?

      # If CAPTCHA is not enabled, pass safely
      return Result.new(success?: true) unless enabled?

      if token.blank?
        return Result.new(success?: false, error_message: "Please complete the CAPTCHA challenge.")
      end

      secret = secret_key
      if secret.blank?
        Rails.logger.warn("[CaptchaVerifier] CAPTCHA enabled without secret key configured.")
        return Result.new(success?: false, error_message: "CAPTCHA service is misconfigured.")
      end

      response = request_verification(secret, token, remote_ip)
      parse_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, StandardError => e
      Rails.logger.error("[CaptchaVerifier] Turnstile request failed: #{e.class} - #{e.message}")
      Result.new(success?: false, error_message: "We couldn't verify that you're human. Please try again.")
    end

    private

    def request_verification(secret, token, remote_ip)
      return request_handler.call(secret, token, remote_ip) if request_handler.present?

      uri = URI.parse(VERIFY_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 3
      http.read_timeout = 3

      request = Net::HTTP::Post.new(uri.request_uri)
      payload = {
        "secret" => secret,
        "response" => token
      }
      payload["remoteip"] = remote_ip if remote_ip.present?

      request.set_form_data(payload)
      http.request(request)
    end

    def parse_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        return Result.new(success?: false, error_message: "We couldn't verify that you're human. Please try again.")
      end

      data = JSON.parse(response.body) rescue nil
      if data && data["success"] == true
        Result.new(success?: true)
      else
        error_codes = data ? Array(data["error-codes"]) : []
        msg = if error_codes.include?("timeout-or-duplicate")
          "CAPTCHA challenge expired. Please verify again."
        else
          "We couldn't verify that you're human. Please try again."
        end
        Result.new(success?: false, error_message: msg)
      end
    end
  end
end
