# Class & Code Guide

A comprehensive, class-by-class reference guide detailing the responsibilities, associations, validations, key methods, callers, and database interactions of all core classes in the codebase.

---

## 1. Domain Models (`app/models/`)

### `Customer`
- **File**: [`app/models/customer.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/customer.rb)
- **Responsibility**: Represents the organizational tenant boundary in the B2B SaaS architecture.
- **Associations**:
  - `has_many :users, dependent: :destroy`
  - `has_many :surveys, dependent: :destroy`
  - `has_many :submissions, through: :surveys`
  - `has_many :survey_daily_metrics, through: :surveys, source: :daily_metrics`
- **Validations**: `validates :name, presence: true`
- **Database Table**: `customers`
- **Why It Exists**: Forms the root of all tenant-isolated data. All surveys, submissions, users, and metrics belong to a customer.

---

### `User`
- **File**: [`app/models/user.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/user.rb)
- **Responsibility**: Represents an authenticated operator belonging to a customer tenant.
- **Associations**:
  - `belongs_to :customer`
- **Validations**:
  - `name`: presence
  - `email`: presence, case-insensitive uniqueness, format via `URI::MailTo::EMAIL_REGEXP`
  - `password`: minimum 6 characters (on create or when updated)
- **Key Methods / Features**:
  - `has_secure_password`: Integrates BCrypt password hashing via `password_digest`.
  - `normalizes :email, with: ->(email) { email.to_s.strip.downcase }`: Automatically strips whitespace and downcases emails.
- **Database Table**: `users`
- **Why It Exists**: Allows users to log in to the application and scopes their access strictly to their parent customer.

---

### `Survey`
- **File**: [`app/models/survey.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/survey.rb)
- **Responsibility**: Manages survey metadata, publication state, questions, submissions, and respondent token digests.
- **Associations**:
  - `belongs_to :customer`
  - `has_many :questions, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :survey`
  - `has_many :submissions, dependent: :destroy`
  - `has_many :answers, through: :submissions`
  - `has_many :daily_metrics, class_name: "SurveyDailyMetric", dependent: :destroy`
- **Nested Attributes**: `accepts_nested_attributes_for :questions, allow_destroy: true, reject_if: :all_blank`
- **Enums**: `enum :status, { draft: 0, published: 1 }, default: :draft`
- **Validations**:
  - `title`: presence
  - `status`: presence
  - `public_token`: presence, uniqueness
  - `limit_one_response_per_device`: boolean inclusion
- **Callbacks**: `before_validation :ensure_public_token, on: :create`
- **Key Methods**:
  - `self.respondent_token_digest(survey_id, token)`: Computes `Digest::SHA256.hexdigest("#{survey_id}:#{token}")` for anonymous device submission limiting.
  - `publishable?`: Validates that the survey contains at least one question and all multiple-choice questions have at least one option.
  - `publish!`: Updates `status: :published, published_at: Time.current` if publishable.
- **Database Table**: `surveys`
- **Why It Exists**: Acts as the central entity for survey configuration, public link distribution, and response collection.

---

### `Question`
- **File**: [`app/models/question.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/question.rb)
- **Responsibility**: Represents an individual ordered question within a survey.
- **Associations**:
  - `belongs_to :survey`
  - `has_many :question_options, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :question`
  - `has_many :answers, dependent: :destroy`
- **Nested Attributes**: `accepts_nested_attributes_for :question_options, allow_destroy: true, reject_if: :all_blank`
- **Enums**: `enum :question_type, { text: 0, number: 1, multiple_choice: 2 }, default: :text`
- **Validations**:
  - `question_text`: presence
  - `question_type`: presence
  - `position`: presence, integer >= 1
  - Custom validation `validate_options_for_question_type`: Disallows options on non-multiple-choice questions.
- **Database Table**: `questions`
- **Why It Exists**: Normalizes survey questions, supporting typed validation and dynamic ordering via `position`.

---

### `QuestionOption`
- **File**: [`app/models/question_option.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/question_option.rb)
- **Responsibility**: Represents a selectable choice for a multiple-choice question.
- **Associations**:
  - `belongs_to :question`
  - `has_many :answers, foreign_key: :selected_option_id, dependent: :nullify`
- **Validations**:
  - `label`: presence
  - `position`: presence, integer >= 1
  - Custom validation `question_must_be_multiple_choice`: Ensures parent question type is multiple choice.
- **Database Table**: `question_options`
- **Why It Exists**: Normalizes choices so options can be labeled, ordered, and linked to answers via foreign keys.

---

### `Submission`
- **File**: [`app/models/submission.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/submission.rb)
- **Responsibility**: Represents a single completed response session to a survey.
- **Associations**:
  - `belongs_to :survey`
  - `has_many :answers, dependent: :destroy, inverse_of: :submission`
- **Validations**:
  - `submitted_at`: presence
  - `respondent_token_digest`: unique scoped to `survey_id` (allow nil)
- **Callbacks**:
  - `before_validation :set_submitted_at, on: :create`
  - `after_commit :enqueue_daily_metric_update, on: :create`
- **Scopes**: `scope :recent, -> { order(submitted_at: :desc) }`
- **Key Methods**:
  - `enqueue_daily_metric_update`: Asynchronously enqueues `UpdateSurveyDailyMetricJob.perform_later(survey_id, date_val)`.
- **Database Table**: `submissions`
- **Why It Exists**: Encapsulates a respondent's submission session and timestamps when the response occurred.

---

### `Answer`
- **File**: [`app/models/answer.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/answer.rb)
- **Responsibility**: Stores the discrete answer value for a specific question within a submission session.
- **Associations**:
  - `belongs_to :submission`
  - `belongs_to :question`
  - `belongs_to :selected_option, class_name: "QuestionOption", optional: true`
- **Validations**:
  - Custom validation `validate_value_type_matches_question`: Enforces that text questions populate only `text_value`, number questions populate only `number_value`, and multiple-choice questions populate only `selected_option_id` (verifying option belongs to question).
- **Key Methods**:
  - `display_value`: Returns formatted string based on question type (text string, number string, or option label).
- **Database Table**: `answers`
- **Why It Exists**: Normalizes answer storage with native SQL data types, enabling accurate math, referential integrity, and efficient indexing.

---

### `SurveyDailyMetric`
- **File**: [`app/models/survey_daily_metric.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/models/survey_daily_metric.rb)
- **Responsibility**: Stores pre-aggregated daily response counters for instantaneous analytics reporting.
- **Associations**:
  - `belongs_to :survey`
- **Validations**:
  - `date`: presence
  - `response_count`: integer >= 0
  - `survey_id`: unique scoped to `date`
- **Key Methods**:
  - `self.increment_response_count(survey_id, date)`: Executes atomic, parameterized PostgreSQL UPSERT (`ON CONFLICT (survey_id, date) DO UPDATE SET response_count = response_count + 1`).
- **Database Table**: `survey_daily_metrics`
- **Why It Exists**: Prevents expensive full-table scans over raw submissions during analytics dashboard page loads.

---

## 2. Controllers (`app/controllers/`)

### `ApplicationController`
- **File**: [`app/controllers/application_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/application_controller.rb)
- **Responsibility**: Base controller providing authentication helpers, tenant context, and browser restrictions.
- **Helper Methods**:
  - `current_user`: Returns cached `User.find_by(id: session[:user_id])`.
  - `current_customer`: Returns `current_user&.customer`.
  - `logged_in?`: Returns `current_user.present?`.
  - `authenticate_user!`: Enforces login, redirecting unauthenticated users to `/login`.

---

### `SessionsController`
- **File**: [`app/controllers/sessions_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/sessions_controller.rb)
- **Responsibility**: Handles operator login and logout.
- **Actions**:
  - `new`: Renders login form (redirects to `/dashboard` if already logged in).
  - `create`: Verifies email and password using `user&.authenticate`, calls `reset_session` (fixation defense), sets `session[:user_id]`, and redirects to `/dashboard`.
  - `destroy`: Calls `reset_session` and redirects to `/login`.

---

### `DashboardController`
- **File**: [`app/controllers/dashboard_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/dashboard_controller.rb)
- **Responsibility**: Renders the tenant overview dashboard.
- **Actions**:
  - `index`: Loads survey counts (total, published, draft), total submissions, and recent surveys strictly scoped to `current_customer`.

---

### `SurveysController`
- **File**: [`app/controllers/surveys_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/surveys_controller.rb)
- **Responsibility**: Manages the complete survey lifecycle for authenticated tenant operators.
- **Actions**:
  - `index`: Lists surveys belonging to `current_customer`.
  - `show`: Displays survey details, question list, public link, and response count.
  - `new` / `create`: Renders form and creates survey with nested questions and options.
  - `edit` / `update`: Updates survey title, settings, and nested questions.
  - `destroy`: Deletes survey and cascades deletion to child records.
  - `publish`: Calls `@survey.publish!`, validating question requirements and transitioning status.
- **Tenant Scoping Filter**:
  ```ruby
  def set_survey
    @survey = current_customer.surveys.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to surveys_path, alert: "Survey not found."
  end
  ```

---

### `SubmissionsController`
- **File**: [`app/controllers/submissions_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/submissions_controller.rb)
- **Responsibility**: Displays survey submissions and detailed answer breakdowns for customer operators.
- **Actions**:
  - `index`: Paginated list of submissions using Pagy 9 with input sanitization and eager loading (`includes(answers: %i[question selected_option])`).
  - `show`: Loads single submission and aligns answers with questions, gracefully handling optional unanswered questions.
- **Tenant & Survey Scoping**:
  - `@survey = current_customer.surveys.find(params[:survey_id])`
  - `@submission = @survey.submissions.find(params[:id])`
  - Fully protects against cross-tenant and cross-survey IDOR.

---

### `PublicSurveysController`
- **File**: [`app/controllers/public_surveys_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/public_surveys_controller.rb)
- **Responsibility**: Public, unauthenticated endpoint allowing anonymous respondents to view and complete published surveys.
- **Security Protections**:
  - IP Rate Limiting (Rack/Rails 8): 60/min for `show`/`success`, 10/min for `submit`.
  - Bot Defense: `CaptchaVerifier.verify` (Cloudflare Turnstile).
  - Multiple Response Cookie Defense: `cookies.signed[:survey_respondent_token]` + SHA256 digest + unique index.
- **Actions**:
  - `show`: Finds `Survey.published.find_by!(public_token: params[:public_token])`.
  - `submit`: Delegates submission to `SubmitSurvey.new(@survey, params[:answers], ...).call`.
  - `success`: Displays thank-you confirmation.

---

### `AnalyticsController`
- **File**: [`app/controllers/analytics_controller.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/controllers/analytics_controller.rb)
- **Responsibility**: Provides high-performance analytics dashboards with date range filtering.
- **Actions**:
  - `index`: Queries `current_customer.survey_daily_metrics` across selected date range (`30d`, `90d`, `ytd`, `all`, or custom). Computes total responses, daily average, active days count, peak day, and per-survey response breakdown.

---

## 3. Service Objects (`app/services/`)

### `SubmitSurvey`
- **File**: [`app/services/submit_survey.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/services/submit_survey.rb)
- **Responsibility**: Coordinates transactional creation of `Submission` and `Answer` records.
- **Key Method**: `call`
  - Encloses creation in `ActiveRecord::Base.transaction`.
  - Enforces required questions.
  - Sanitizes and validates typed inputs (text whitespace, number regex/BigDecimal, multiple-choice option ownership).
  - Handles `ActiveRecord::RecordNotUnique` gracefully for race conditions on duplicate device submission tokens.
  - Returns `Result` struct (`success?`, `submission`, `errors`).

---

### `CaptchaVerifier`
- **File**: [`app/services/captcha_verifier.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/services/captcha_verifier.rb)
- **Responsibility**: Validates Cloudflare Turnstile CAPTCHA tokens via HTTP POST to `challenges.cloudflare.com`.
- **Key Methods**:
  - `enabled?`: Checks if Turnstile credentials or test mocks are configured.
  - `verify(token, remote_ip:)`: Performs HTTP verification or returns test mock result.
  - `with_mock(success:, error_message:)`: Allows integration and system tests to simulate passed or failed challenges without outbound HTTP requests.

---

## 4. Background Jobs (`app/jobs/`)

### `UpdateSurveyDailyMetricJob`
- **File**: [`app/jobs/update_survey_daily_metric_job.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/jobs/update_survey_daily_metric_job.rb)
- **Responsibility**: Asynchronously updates pre-aggregated daily metrics after a submission is committed.
- **Key Method**: `perform(survey_id, date_str)`
  - Parses date and calls `SurveyDailyMetric.increment_response_count(survey.id, date)`.

---

## 5. JavaScript Controllers (`app/javascript/controllers/`)

### `survey_builder_controller.js`
- **File**: [`app/javascript/controllers/survey_builder_controller.js`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/app/javascript/controllers/survey_builder_controller.js)
- **Responsibility**: Stimulus controller managing client-side dynamic addition and removal of questions and multiple-choice options.
- **Key Actions**:
  - `addQuestion`: Clones question template, generates unique timestamp index, appends to DOM.
  - `removeQuestion`: Marks `_destroy` input and hides question card.
  - `handleTypeChange`: Toggles visibility of options container when type changes to `multiple_choice`.
  - `addOption`: Clones option template, generates unique timestamp index, appends to options container.
  - `removeOption`: Marks option `_destroy` and hides row.

---

## 6. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Application Flow](APPLICATION_FLOW.md)
- [Database Design](DATABASE_DESIGN.md)
- [Code Walkthrough](CODE_WALKTHROUGH.md)
