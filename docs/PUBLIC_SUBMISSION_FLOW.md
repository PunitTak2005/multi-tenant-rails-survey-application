# Public Survey Submission Flow & Bot Defense

This document details the public respondent journey, rate limiting, bot protection, device submission restrictions, and transactional response persistence in the application.

---

## 1. Public Submission Architecture

```text
[ Anonymous Respondent ]
          │
          ▼
   GET /s/:public_token
          │
   ┌──────┴───────────────────────────────────────────────────────┐
   │ 1. IP Rate Limit: 60/min                                      │
   │ 2. Find Survey: Survey.published.find_by!(public_token: ...) │
   │ 3. Eager load: questions.includes(:question_options)         │
   └──────┬───────────────────────────────────────────────────────┘
          │
          ▼ (renders public_surveys/show)
   Respondent Enters Answers
          │
          ▼
   POST /s/:public_token
          │
   ┌──────┴───────────────────────────────────────────────────────┐
   │ 1. IP Rate Limit: 10/min                                      │
   │ 2. CaptchaVerifier (Cloudflare Turnstile token verification)  │
   │ 3. Multiple Response Defense (signed cookie & SHA256 digest)  │
   │ 4. SubmitSurvey.call (ActiveRecord::Base.transaction)        │
   │    - Validate required questions                              │
   │    - Type validate: Text, Number (BigDecimal), MC Option ID   │
   │    - INSERT submission                                        │
   │    - INSERT answers                                           │
   │    - COMMIT (or ROLLBACK on error)                            │
   └──────┬───────────────────────────────────────────────────────┘
          │
   ┌──────┴────────────────────────────────────────┐
   │ 5. Submission#after_commit:                   │
   │    Enqueue UpdateSurveyDailyMetricJob         │
   │ 6. Set signed cookie (1 year expiry)          │
   │ 7. 302 Redirect to /s/:public_token/success   │
   └───────────────────────────────────────────────┘
```

---

## 2. Unauthenticated Rate Limiting (Rails 8 Native)

Public endpoints are inherently susceptible to denial-of-service (DoS) and rapid-fire spam. The application leverages Rails 8 built-in ActionController rate limiting:

```ruby
# app/controllers/public_surveys_controller.rb
rate_limit to: 60, within: 1.minute,
           by: -> { "#{request.remote_ip}:#{params[:public_token]}" },
           with: :render_rate_limited,
           only: %i[show success]

rate_limit to: 10, within: 1.minute,
           by: -> { "#{request.remote_ip}:#{params[:public_token]}" },
           with: :render_rate_limited,
           only: :submit
```

- **Compound Key**: Rate limits are scoped by `IP:public_token`, meaning an active respondent on Survey A does not exhaust their limit on Survey B.
- **Strict Limit on Submissions**: 10 submissions per minute per IP prevents automated form stuffing.
- **Graceful 429 Response**: Sets `Retry-After: 60` HTTP header and renders a user-friendly `429 Too Many Requests` page.

---

## 3. Bot Defense: Cloudflare Turnstile (`CaptchaVerifier`)

To prevent automated bot spam from submitting dummy responses, the application integrates Cloudflare Turnstile via the `CaptchaVerifier` service:

```ruby
# app/services/captcha_verifier.rb
class CaptchaVerifier
  VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  ...
  def verify(token, remote_ip: nil)
    return mock_result if mock_result.present?
    return Result.new(success?: true) unless enabled?

    uri = URI(VERIFY_URL)
    response = Net::HTTP.post_form(uri, {
      "secret" => secret,
      "response" => token,
      "remoteip" => remote_ip
    })
    ...
  end
end
```

- **Privacy-Preserving**: Unlike legacy CAPTCHAs, Turnstile verifies human visitors without presenting frustrating puzzle challenges.
- **Environment Driven**: Enabled automatically when `ENV["TURNSTILE_SECRET_KEY"]` is supplied.
- **Test Harness**: Supports isolated testing without outbound network calls via `CaptchaVerifier.with_mock(success: true)`.

---

## 4. Privacy-Preserving Multiple Response Prevention (Signed Cookie)

Surveys can optionally restrict respondents to **one response per device/browser** (`limit_one_response_per_device: true`):

### How It Works:
1. When a respondent visits the survey, the application inspects `cookies.signed[:survey_respondent_token]`.
2. If no token exists, an unpredictable 24-byte hex token is generated: `SecureRandom.hex(24)`.
3. The token is hashed with the survey ID to produce a deterministic digest:
   ```ruby
   Survey.respondent_token_digest(@survey.id, respondent_token)
   # Digest::SHA256.hexdigest("#{survey_id}:#{token}")
   ```
4. **Pre-Submission Check**: If `submissions.exists?(respondent_token_digest: digest)` is true, the submission is rejected with `"You have already submitted this survey from this browser."`
5. **Database Partial Unique Index**: To prevent race conditions where two tabs submit simultaneously:
   ```sql
   CREATE UNIQUE INDEX index_submissions_on_survey_and_respondent_digest
   ON submissions (survey_id, respondent_token_digest)
   WHERE (respondent_token_digest IS NOT NULL);
   ```
6. **Privacy Preservation**: The cookie does not track personal identifiers, IP addresses, or cross-site behavior. It only acts as an anonymous, cryptographic token scoped to that device.

---

## 5. The `SubmitSurvey` Transactional Engine

The core persistence logic is encapsulated in `app/services/submit_survey.rb`:

```ruby
class SubmitSurvey
  def call
    ...
    ActiveRecord::Base.transaction do
      submission = @survey.submissions.build(
        submitted_at: Time.current,
        respondent_token_digest: @respondent_token_digest
      )

      @survey.questions.includes(:question_options).each do |question|
        raw_val = @answer_params[question.id.to_s]

        # Enforce required fields
        if question.required? && raw_val.blank?
          submission.errors.add(:base, "Question '#{question.question_text}' is required.")
        end

        next if raw_val.blank?

        answer = submission.answers.build(question: question)

        case question.question_type.to_sym
        when :text
          answer.text_value = raw_val.to_s.strip
        when :number
          num_str = raw_val.to_s.strip
          if num_str !~ /\A-?\d+(\.\d+)?\z/
            submission.errors.add(:base, "Answer for '#{question.question_text}' must be a valid number.")
          else
            answer.number_value = BigDecimal(num_str)
          end
        when :multiple_choice
          option_id = raw_val.to_i
          valid_option = question.question_options.find { |opt| opt.id == option_id }
          if valid_option.nil?
            submission.errors.add(:base, "Selected option for '#{question.question_text}' is invalid.")
          else
            answer.selected_option = valid_option
          end
        end
      end

      raise ActiveRecord::Rollback if submission.errors.any?

      unless submission.save
        raise ActiveRecord::Rollback
      end
    end
    ...
  end
end
```

### Key Guarantees:
1. **Atomicity**: Either the `Submission` and ALL of its `Answer` records are saved successfully, or nothing is written to the database.
2. **Strict Question Type Enforcement**:
   - Multiple choice inputs cannot inject non-existent options or options belonging to another question.
   - Numeric inputs are verified by regex and cast to `BigDecimal` to prevent float corruption.
3. **Rollback on Error**: If any answer fails validation, `ActiveRecord::Rollback` leaves the database completely clean.

---

## 6. Post-Commit Asynchronous Analytics Trigger

Once the transaction is successfully committed to PostgreSQL, the submission invokes its post-commit hook:

```ruby
# app/models/submission.rb
after_commit :enqueue_daily_metric_update, on: :create

private

def enqueue_daily_metric_update
  date_val = (submitted_at || Time.current).to_date.to_s
  UpdateSurveyDailyMetricJob.perform_later(survey_id, date_val)
end
```

- **Why `after_commit`**: Calling background jobs inside an open transaction is an anti-pattern. If the worker picks up the job before the database commits, the record is not visible. `after_commit` ensures the record is fully committed and visible to background workers.

---

## 7. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Submissions & Responses](SUBMISSIONS_AND_RESPONSES.md)
- [Analytics Flow](ANALYTICS_FLOW.md)
- [Security Architecture](SECURITY.md)
