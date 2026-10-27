# Complete Application Flows & Request Lifecycles

This document describes the complete operational flows of the application, walking through every user journey, controller transition, database interaction, and background process.

---

## 1. Flow Overview & Global Route Map

The application divides its surface area into **Private Authenticated Routes** (accessible only by logged-in tenant operators) and **Public Anonymous Routes** (accessible to survey respondents without accounts):

| Verb | Path | Controller#Action | Access | Purpose |
| :--- | :--- | :--- | :---: | :--- |
| `GET` | `/login` | `sessions#new` | Public | Operator login form |
| `POST` | `/login` | `sessions#create` | Public | Authenticates credentials and starts session |
| `DELETE` | `/logout` | `sessions#destroy` | Private | Clears session and logs out operator |
| `GET` | `/` or `/dashboard` | `dashboard#index` | Private | Tenant overview dashboard & key metrics |
| `GET` | `/surveys` | `surveys#index` | Private | Lists surveys owned by current customer |
| `GET` | `/surveys/new` | `surveys#new` | Private | Renders dynamic survey creation form |
| `POST` | `/surveys` | `surveys#create` | Private | Persists new survey and nested questions |
| `GET` | `/surveys/:id` | `surveys#show` | Private | Shows survey details, question list, public URL |
| `GET` | `/surveys/:id/edit` | `surveys#edit` | Private | Form to update title, questions, options |
| `PATCH` | `/surveys/:id` | `surveys#update` | Private | Updates survey and nested questions |
| `DELETE` | `/surveys/:id` | `surveys#destroy` | Private | Deletes survey and cascades to all child records |
| `POST` | `/surveys/:id/publish` | `surveys#publish` | Private | Validates and transitions survey to `published` |
| `GET` | `/surveys/:survey_id/submissions` | `submissions#index` | Private | Paginated list of responses for a survey |
| `GET` | `/surveys/:survey_id/submissions/:id` | `submissions#show` | Private | Detailed answer breakdown for a single response |
| `GET` | `/analytics` | `analytics#index` | Private | Daily response volume, trends, date range filters |
| `GET` | `/s/:public_token` | `public_surveys#show` | Public | Publicly accessible survey response form |
| `POST` | `/s/:public_token` | `public_surveys#submit` | Public | Submits respondent answers (transactional) |
| `GET` | `/s/:public_token/success` | `public_surveys#success` | Public | Thank-you confirmation screen |

---

## 2. Flow 1: Login & Operator Authentication

```text
Browser User                    SessionsController              PostgreSQL (users)
     │                                  │                               │
     │── GET /login ───────────────────>│                               │
     │   (renders sessions/new)         │                               │
     │                                  │                               │
     │── POST /login (email, pass) ────>│                               │
     │                                  │── User.find_by(email: ...) ──>│
     │                                  │<── user record (with hash) ───│
     │                                  │                               │
     │                             user.authenticate(params[:password]) │
     │                                  │                               │
     │                             reset_session                        │
     │                             session[:user_id] = user.id          │
     │<── 302 Redirect (/dashboard) ────│                               │
```

1. **Entry**: User visits `GET /login`. If the session is already authenticated (`logged_in?` is true), the user is immediately redirected to `/dashboard`.
2. **Submission**: User submits email and plain-text password via `POST /login`.
3. **Lookup**: `SessionsController#create` normalizes the email (`strip.downcase`) and executes:
   ```ruby
   user = User.find_by(email: params[:email]&.to_s&.strip&.downcase)
   ```
4. **BCrypt Verification**: `user&.authenticate(params[:password])` uses `BCrypt::Password` to compute the salted SHA hash of the provided password and compare it in constant time against `password_digest`.
5. **Session Fixation Defense**: Upon successful verification, `reset_session` is called to destroy any existing session cookie ID, generating a brand new session identifier before assigning `session[:user_id] = user.id`.
6. **Redirect**: Redirects to `dashboard_path` with flash notice `"Welcome back, #{user.name}!"`.

---

## 3. Flow 2: Customer Dashboard

1. **Authentication Guard**: `DashboardController` invokes `before_action :authenticate_user!`. If `session[:user_id]` is absent or invalid, the request redirects to `login_path` with an alert.
2. **Tenant Scoping**: All metric queries originate strictly from `current_customer`:
   ```ruby
   @customer = current_customer
   @total_surveys = current_customer.surveys.count
   @published_surveys = current_customer.surveys.published.count
   @draft_surveys = current_customer.surveys.draft.count
   @total_submissions = current_customer.submissions.count
   @recent_surveys = current_customer.surveys.recent.limit(5).includes(:questions, :submissions)
   ```
3. **Rendering**: Renders `app/views/dashboard/index.html.erb`, displaying tenant statistics and quick links to manage surveys, inspect submissions, and review analytics.

---

## 4. Flow 3 & 4: Survey & Question Creation

```text
Browser User                     SurveysController               PostgreSQL
     │                                  │                               │
     │── GET /surveys/new ─────────────>│                               │
     │   (builds @survey & Q1)          │                               │
     │<── renders surveys/new ──────────│                               │
     │                                  │                               │
     │ [Stimulus dynamically adds Qs]   │                               │
     │                                  │                               │
     │── POST /surveys ────────────────>│                               │
     │   (nested questions_attributes)  │── current_customer.surveys.build
     │                                  │   @survey.save!               │
     │                                  │── INSERT INTO surveys ───────>│
     │                                  │── INSERT INTO questions ─────>│
     │                                  │── INSERT INTO options ───────>│
     │<── 302 Redirect (/surveys/:id) ──│                               │
```

1. **Form Rendering (`surveys#new`)**:
   - `SurveysController#new` builds `@survey = current_customer.surveys.build` and pre-populates one default text question.
   - The view uses Rails form helper `form_with(model: @survey)` connected to the Stimulus JS controller `survey-builder`.
2. **Client-Side Question Building**:
   - The user can dynamically add questions of type **Text**, **Number**, or **Multiple Choice**.
   - If **Multiple Choice** is selected, options fields dynamically appear.
   - Stimulus clones HTML `<template>` tags, substituting unique timestamp keys (e.g. `NEW_RECORD`) for Rails nested attribute binding.
3. **Strong Parameters & Nested Attributes**:
   - `Survey` defines `accepts_nested_attributes_for :questions, allow_destroy: true`.
   - `Question` defines `accepts_nested_attributes_for :question_options, allow_destroy: true`.
   - `SurveysController#survey_params` safely permits the complete nested structure:
     ```ruby
     params.require(:survey).permit(
       :title, :description, :limit_one_response_per_device,
       questions_attributes: [
         :id, :question_text, :question_type, :position, :required, :_destroy,
         { question_options_attributes: %i[id label position _destroy] }
       ]
     )
     ```
4. **Public Token Generation**:
   - On creation, `Survey#before_validation :ensure_public_token` generates an unguessable 16-byte URL-safe base64 string (`SecureRandom.urlsafe_base64(12)`) if not already present.
5. **Persistence**: In a single database transaction, Rails inserts the `surveys` row, followed by `questions` rows, followed by `question_options` rows.

---

## 5. Flow 5: Publishing a Survey

A survey is created in `status: :draft` (integer `0`). It cannot receive public submissions until published.

1. **Trigger**: User clicks "Publish Survey" (`POST /surveys/:id/publish`).
2. **Tenant Scoping**: `SurveysController#set_survey` locates the survey via `current_customer.surveys.find(params[:id])`.
3. **Publication Validation (`Survey#publish!`)**:
   ```ruby
   def publishable?
     errors.clear
     errors.add(:base, "Survey must have at least one question to be published.") if questions.reload.empty?

     questions.each do |q|
       if q.multiple_choice? && q.question_options.reload.empty?
         errors.add(:base, "Multiple choice question '#{q.question_text.truncate(30)}' must have at least one option.")
       end
     end

     errors.empty?
   end
   ```
4. **State Transition**: If valid, `update!(status: :published, published_at: Time.current)` transitions status to `1`.
5. **Public Access Granted**: The public link `http://localhost:3000/s/:public_token` is now active.

---

## 6. Flow 6: Public Survey Submission (The Core Respondent Flow)

```text
Anonymous Respondent           PublicSurveysController         SubmitSurvey Service            PostgreSQL
        │                                 │                             │                           │
        │── GET /s/:public_token ────────>│                             │                           │
        │   (Rate limit: 60/min)          │── Survey.published.find ────┼──────────────────────────>│
        │<── 200 OK (renders form) ───────│                             │                           │
        │                                 │                             │                           │
        │── POST /s/:public_token ───────>│                             │                           │
        │   (Rate limit: 10/min)          │                             │                           │
        │                                 │── CaptchaVerifier.verify ───│                           │
        │                                 │── Check Device Cookie ──────│                           │
        │                                 │── SubmitSurvey.new.call ───>│                           │
        │                                 │                             │── BEGIN TRANSACTION ─────>│
        │                                 │                             │── INSERT submission ─────>│
        │                                 │                             │── INSERT answers (1..N) ─>│
        │                                 │                             │── COMMIT ────────────────>│
        │                                 │<── Result(success: true) ───│                           │
        │                                 │                             │                           │
        │                                 │                             │── (after_commit) ────────>│
        │                                 │                             │   Enqueue UpdateSurveyJob │
        │                                 │── Set signed cookie ────────│                           │
        │<── 302 Redirect (/success) ─────│                             │                           │
```

1. **Display (`public_surveys#show`)**:
   - The respondent visits `/s/:public_token`. No authentication required.
   - Rails applies IP rate limiting (60 requests/minute per IP + token).
   - Looks up `Survey.published.find_by!(public_token: params[:public_token])`. If draft or non-existent, renders `404 Not Found`.
2. **Submission (`public_surveys#submit`)**:
   - Rate limited to 10 submissions/minute.
   - **Bot Check**: If enabled, `CaptchaVerifier` verifies Cloudflare Turnstile token.
   - **Multiple Response Check**: If `@survey.limit_one_response_per_device?`, checks `cookies.signed[:survey_respondent_token]`. Computes SHA256 digest `Survey.respondent_token_digest(@survey.id, token)` and checks if `submissions.exists?(respondent_token_digest: digest)`.
   - **Execution via `SubmitSurvey` Service**:
     - Executes inside `ActiveRecord::Base.transaction`.
     - Validates required questions are answered.
     - Enforces question types:
       - **Text**: Whitespace trimmed.
       - **Number**: Validates regex `/\A-?\d+(\.\d+)?\z/` and casts to `BigDecimal`.
       - **Multiple Choice**: Verifies that the selected `option_id` belongs to `question.question_options`.
     - Inserts the `Submission` row and corresponding `Answer` rows.
     - If any answer validation fails, `raise ActiveRecord::Rollback` rolls back the transaction.
   - **Post-Commit Hook**:
     - `Submission#after_commit on: :create` enqueues `UpdateSurveyDailyMetricJob.perform_later(survey_id, date)`.
   - **Cookie Setting**: If device restriction is enabled, sets signed cookie `cookies.signed[:survey_respondent_token]` expiring in 1 year.
   - **Redirect**: Redirects to `public_survey_success_path(@survey.public_token)`.

---

## 7. Flow 7 & 8: Viewing Submissions & Details

1. **Submissions Listing (`submissions#index`)**:
   - Accessible via `/surveys/:survey_id/submissions`.
   - Protected by `before_action :authenticate_user!` and tenant lookup `@survey = current_customer.surveys.find(params[:survey_id])`.
   - **Pagy Pagination**: Sanitizes `params[:page]` and `params[:limit]` (default 20, max 100).
   - **Eager Loading**: `includes(answers: %i[question selected_option])` prevents N+1 queries when rendering submission dates and answer previews.
2. **Submission Detail (`submissions#show`)**:
   - Scoped lookup: `@submission = @survey.submissions.find(params[:id])`. Prevents cross-tenant and cross-survey IDOR.
   - **Handling Optional Unanswered Questions**:
     ```ruby
     existing_answers = @submission.answers.includes(:question, :selected_option).index_by(&:question_id)
     @answers = @survey.questions.order(:position).includes(:question_options).map do |question|
       existing_answers[question.id] || @submission.answers.build(question: question)
     end
     ```
   - Matches every survey question to its answer. If an optional question was left unanswered by the respondent, an unpersisted placeholder is built, displaying `"Not answered"` in the UI.

---

## 8. Flow 9: High-Scale Analytics

```text
Submission Committed
        │
        ▼ (after_commit)
UpdateSurveyDailyMetricJob (ActiveJob)
        │
        ▼
SurveyDailyMetric.increment_response_count (PostgreSQL Atomic UPSERT)
INSERT ... ON CONFLICT (survey_id, date) DO UPDATE SET response_count = response_count + 1
        │
        ▼
Analytics Dashboard Query (/analytics)
current_customer.survey_daily_metrics.where(date: start_date..end_date).group(:date).sum(:response_count)
```

1. **Data Source**: Reads directly from `survey_daily_metrics` pre-aggregated table, avoiding expensive full-table scans across millions of raw submissions.
2. **Date Range Filtering**:
   - **Presets**: `30d`, `90d` (default), `ytd` (Year-to-Date), `all` (All time).
   - **Custom Date Range**: `start_date` and `end_date` parameters with strict ISO8601 validation (`Date.iso8601`) and order checking (`start_date <= end_date`).
3. **Calculated Metrics**:
   - **Total Responses**: Sum of `response_count` within selected date window.
   - **Average Daily Responses**: Total responses divided by window days.
   - **Active Days**: Count of calendar dates with at least 1 submission.
   - **Peak Response Day**: Date and count with highest volume.
   - **Per-Survey Breakdown**: Individual response count per published survey.

---

## 9. Comprehensive Request Lifecycle Example: Public Submission

Here is the exact lifecycle of a `POST /s/acme-csat-2026` request from wire to database:

1. **TCP Connection & TLS**: Rack and Puma 8.0 receive the HTTP POST request.
2. **ActionDispatch Middleware**:
   - `ActionDispatch::HostAuthorization` verifies the host header.
   - `ActionDispatch::Cookies` reads and decrypts encrypted cookies (`cookies.signed`).
   - `ActionDispatch::Session::CookieStore` prepares the session hash.
   - `ActionDispatch::Request#remote_ip` resolves client IP address.
3. **Rails Routing**: Matches `post "/s/:public_token", to: "public_surveys#submit"` and routes to `PublicSurveysController#submit`.
4. **ActionController Filters**:
   - `rate_limit to: 10, within: 1.minute` checks the cache counter key `rate_limit:public_surveys:submit:127.0.0.1:acme-csat-2026`.
   - `verify_authenticity_token` validates the CSRF authenticity token.
5. **Controller Execution**:
   - Finds `@survey = Survey.published.find_by!(public_token: "acme-csat-2026")`.
   - Inspects `cookies.signed[:survey_respondent_token]`.
   - Calls `SubmitSurvey.new(@survey, params[:answers], respondent_token_digest: digest).call`.
6. **ActiveRecord & Database**:
   - Executes `BEGIN`.
   - Validates required questions and typed answer constraints.
   - Executes `INSERT INTO "submissions" ("survey_id", "submitted_at", "created_at", "updated_at") VALUES ($1, $2, $3, $4) RETURNING "id"`.
   - Executes batch `INSERT INTO "answers" (...) VALUES (...)`.
   - Executes `COMMIT`.
7. **After Commit Callbacks**:
   - `Submission#enqueue_daily_metric_update` queues `UpdateSurveyDailyMetricJob` in ActiveJob.
8. **Controller Response**:
   - Sets encrypted cookie header `Set-Cookie: survey_respondent_token=...; HttpOnly; SameSite=Lax`.
   - Issues HTTP `302 Found` redirect to `/s/acme-csat-2026/success`.
9. **Browser Rendering**: Browser follows redirect to `GET /s/acme-csat-2026/success`, rendering the confirmation template.
