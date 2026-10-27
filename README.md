# Multi-Tenant B2B SaaS Survey Application

A complete, production-quality multi-tenant B2B SaaS survey platform built in **Ruby on Rails** and **PostgreSQL**.

The application allows organizational customers (tenants) to manage users, create surveys with multiple typed questions (text, number, and multiple choice), publish surveys via secure public URLs, and collect anonymous responses while viewing real-time database-aggregated analytics and response breakdowns. Strict multi-tenant isolation is enforced at every boundary.

---

## Architecture Overview

- **Framework**: Ruby on Rails 8.1.4 (Idiomatic Rails MVC, ActiveRecord, ERB, Propshaft, Stimulus & Turbo via Importmap).
- **Ruby Runtime**: Ruby 3.3.6 managed via RVM.
- **Database**: PostgreSQL 16 running locally via Docker Compose.
- **Tenant Isolation**: Strictly scoped queries through authenticated session customer (`current_customer.surveys...`). No raw customer IDs are trusted from client parameters.
- **Authentication**: Built-in Rails secure password authentication with `has_secure_password` (`bcrypt`), session regeneration to prevent fixation, and protected controller filters.
- **Survey Engine**: Dynamic survey builder supporting text, numeric, and multiple-choice questions with normalized, transactional response storage.
- **Public Submissions**: Anonymous respondents access published surveys through secure, unguessable public tokens (`/s/:public_token`). Internal database IDs are never leaked.
- **Analytics**: PostgreSQL date-truncation and grouping aggregations (`GROUP BY DATE(...)`) calculating daily response volume across the past 90 days.

---

## System Requirements

- **Ruby**: `3.3.6`
- **Rails**: `~> 8.1.4`
- **RVM**: `1.29.12` or higher
- **PostgreSQL Client (`psql`)**: `16.x`
- **Docker & Docker Compose**: Docker 29+ / Docker Compose v5+
- **Bundler**: `~> 4.0`

Verify your local environment:

```bash
ruby -v
rails -v
bundle -v
psql --version
docker compose version
```

---

## Setup & Installation

### 1. RVM & Ruby Setup

Install and set the default Ruby version using RVM:

```bash
rvm install 3.3.6
rvm use 3.3.6 --default
gem install bundler
bundle install
```

### 2. Configure Environment Variables

Copy the example environment configuration:

```bash
cp .env.example .env
```

Review `.env` to verify your PostgreSQL settings:

```text
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=multi_tenant_development
POSTGRES_TEST_DB=multi_tenant_test
```

### 3. Start PostgreSQL with Docker Compose

Launch the PostgreSQL 16 container locally:

```bash
docker compose up -d
```

To verify the container is healthy:

```bash
docker compose ps
```

### 4. Create and Migrate Database

Initialize and migrate the PostgreSQL databases:

```bash
bin/rails db:create
bin/rails db:migrate
```

### 5. Seed Initial Data (Recommended)

Generate realistic, deterministic seed data featuring 2 separate customer tenants, users, surveys, questions across all types (Text, Number, Multiple Choice), and 157 historical submissions distributed across the last ~3 months (89 days) to fully demonstrate the Analytics page:

```bash
bin/rails db:seed
```

#### What gets generated:
| Entity / Table | Count | Details |
| :--- | :--- | :--- |
| **`customers`** | 2 | `Acme Corporation` (primary tenant) & `Beta Technologies` (isolation verification tenant) |
| **`users`** | 2 | `admin@acme.test` & `beta_admin@beta.test` (password: `ChangeMe123!`) |
| **`surveys`** | 4 | Acme: 2 published (`acme-csat-2026`, `acme-product-eval`), 1 draft (`acme-draft-roadmap`); Beta: 1 published (`beta-onboarding-survey`) |
| **`questions`** | 7 | Across all supported types: 3 Multiple Choice, 2 Numeric rating/metrics, 2 Freeform text |
| **`question_options`** | 10 | Ordered options for multiple-choice questions (e.g. satisfaction ratings, module selections) |
| **`submissions`** | 157 | Acme CSAT: 130 submissions; Acme Product Eval: 10 submissions; Beta Onboarding: 17 submissions |
| **`answers`** | 403 | Strictly typed responses: 157 MC answers, 157 numeric answers, 89 realistic text feedbacks |
| **`survey_daily_metrics`** | 77 | Pre-aggregated daily response counts automatically synchronized via `Rake::Task["analytics:backfill"]` |

#### Seed Date Distribution & Analytics Readiness:
- **Historical Span**: Spans 89 days (July 30, 2026 to October 27, 2026), satisfying the 3-month analytics requirement.
- **Activity Cadence**: 56 distinct calendar dates with responses (1 to 6 responses per active day).
- **Tenant Isolation**: Acme has 140 submissions and Beta has 17 submissions. Zero records cross tenant boundaries.
- **Idempotency & Re-entrancy**: Seeds clean up existing records using foreign-key cascade order before regenerating deterministic data via a dedicated PRNG (`Random.new(42)`). Re-running `bin/rails db:seed` is completely safe.
- **Automated Verification**: Run `bin/rails test test/models/seed_data_test.rb` (6 tests, 127 assertions).

### 6. Initial Customer & User Setup (Rake Tasks)

The application provides dedicated, idempotent Rake tasks to provision initial customer tenants and users for development and testing:

#### Option A: Quick Dual-Tenant Setup (Recommended for testing isolation)
Provisions two complete customer tenants (`Acme Corporation` and `Beta Technologies`) with credentials ready for immediate login:

```bash
bin/rails customers:setup
```

Output:
```text
Tenant A: Acme Corporation
  Email   : admin@acme.test
  Password: ChangeMe123!

Tenant B: Beta Technologies
  Email   : beta@beta.test
  Password: ChangeMe123!
```

#### Option B: Custom Single Customer & User Provisioning
You can also provision a custom customer tenant and administrator via environment variables:

```bash
INITIAL_CUSTOMER_NAME="Custom Corp" \
INITIAL_USER_EMAIL="admin@custom.test" \
INITIAL_USER_PASSWORD="ChangeMe123!" \
bin/rails customers:create_initial
```

Both tasks are strictly idempotent: re-running them will safely update existing records without creating duplicate customers or users.

> **Note on Scope**: User administration UI, user invitation workflows, and multi-user management screens within the dashboard are intentionally out of scope for this focused SaaS core. Initial tenants and users are managed via these designated Rake tasks and seeds.

---

## Running the Application

Start the Rails Puma web server:

```bash
bin/rails server -b 0.0.0.0 -p 3000
```

Open your browser to:

```text
http://localhost:3000
```

---

## Demo Credentials

The database seed provides two separate customer tenants to demonstrate complete tenant isolation:

### Customer Tenant A (Acme Corporation)
- **Login URL**: `http://localhost:3000/login`
- **Email**: `admin@acme.test`
- **Password**: `ChangeMe123!`
- **Includes**: 3 surveys (2 published, 1 draft), 5 questions, and 140 historical submissions across ~3 months.

### Customer Tenant B (Beta Technologies)
- **Login URL**: `http://localhost:3000/login`
- **Email**: `beta_admin@beta.test`
- **Password**: `ChangeMe123!`
- **Includes**: 1 published survey, 2 questions, and 17 historical submissions isolated to Beta.

---

## Survey Submission Flow

```text
               +--------------------------------------+
               |    Customer User Authenticates       |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |         Customer Dashboard           |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |       Create Survey & Questions      |
               | (Text, Number, and Multiple Choice)  |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |            Publish Survey            |
               | (Generates unique /s/:public_token)  |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |     Anonymous Respondent Visits      |
               |         /s/:public_token             |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |      SubmitSurvey Service Action     |
               | (Transaction: Submissions + Answers) |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |         Success Confirmation         |
               |       /s/:public_token/success       |
               +--------------------------------------+
                                  │
                                  ▼
               +--------------------------------------+
               |      Tenant Views Submissions        |
               |      & Daily Aggregated Analytics    |
               +--------------------------------------+
```

---

## Multi-Tenancy & Security Architecture

### 1. Hard Tenant Scoping
Every authenticated controller action originates directly from the signed-in session:

```ruby
# In ApplicationController
def current_user
  @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
end

def current_customer
  @current_customer ||= current_user&.customer
end
```

All data queries are strictly scoped:

```ruby
# Preferred:
@survey = current_customer.surveys.find(params[:id])
@submissions = @survey.submissions.find(params[:id])

# Forbidden:
# Survey.find(params[:id])
```

If a user from Customer A manipulates URLs or IDs to request an entity owned by Customer B, the query raises `ActiveRecord::RecordNotFound` and safely redirects with an alert. Customer A can never read, modify, or delete Customer B's records.

### 2. Public Submission Security
- Anonymous submissions use an unguessable 16-byte base64 `public_token` (e.g. `/s/acme-csat-2026`). Internal database serial IDs are never exposed.
- Only surveys with status `published` can be viewed or submitted. Draft surveys return `404 Not Found`.
- Option hijacking prevention: `SubmitSurvey` verifies that each submitted option actually belongs to that specific question.
- All submissions execute inside an `ActiveRecord::Base.transaction`. If any answer validation fails (such as an invalid number or missing required field), no partial records are saved.

---

## Database Design

See full ERD and documentation in [docs/DATABASE_DESIGN.md](docs/DATABASE_DESIGN.md).

```text
Customer
  ├── Users
  └── Surveys
        ├── Questions
        │     └── QuestionOptions
        └── Submissions
              └── Answers
```

### Table Summary:
- **`customers`**: Organizational tenants (`id`, `name`, timestamps).
- **`users`**: Tenant users with BCrypt password hashing (`customer_id`, `email`, `password_digest`, `name`).
- **`surveys`**: Tenant surveys (`customer_id`, `title`, `description`, `status`, `public_token`, `published_at`).
- **`questions`**: Ordered questions (`survey_id`, `question_text`, `question_type`, `position`, `required`).
- **`question_options`**: Choices for multiple-choice questions (`question_id`, `label`, `position`).
- **`submissions`**: Response sessions (`survey_id`, `submitted_at`).
- **`answers`**: Normalized answers (`submission_id`, `question_id`, `text_value`, `number_value`, `selected_option_id`).

---

## Scalable Analytics Architecture

To maintain sub-millisecond response times under high-volume production datasets (e.g., hundreds of thousands or millions of submissions), analytics calculations are decoupled from raw submission table scans:

### 1. `survey_daily_metrics` Aggregation Table
Daily response counts are pre-aggregated in a dedicated table with composite unique indexing:
- `survey_id` (foreign key with `on_delete: :cascade`)
- `date` (date, indexed)
- `response_count` (integer, default: 0)
- Compound unique index: `[survey_id, date]`

### 2. Asynchronous Job & Atomic UPSERT
When a respondent completes a survey, the submission transaction commits first. An `after_commit, on: :create` lifecycle callback enqueues `UpdateSurveyDailyMetricJob`:

```ruby
# In app/models/submission.rb
after_commit :enqueue_daily_metric_update, on: :create

def enqueue_daily_metric_update
  UpdateSurveyDailyMetricJob.perform_later(survey_id, (submitted_at || Time.current).to_date.to_s)
end
```

The job executes a PostgreSQL atomic `UPSERT` to guarantee zero lost updates even under high concurrency:

```sql
INSERT INTO survey_daily_metrics (survey_id, date, response_count, created_at, updated_at)
VALUES ($1, $2, 1, NOW(), NOW())
ON CONFLICT (survey_id, date)
DO UPDATE SET response_count = survey_daily_metrics.response_count + 1,
              updated_at = NOW();
```

### 3. Analytics Dashboard Query
`AnalyticsController#index` queries pre-aggregated `survey_daily_metrics` buckets scoped strictly through `current_customer`:

```ruby
@daily_responses = current_customer.survey_daily_metrics
                                   .where(date: @start_date..@end_date)
                                   .group(:date)
                                   .order(date: :desc)
                                   .sum(:response_count)
```

This ensures dashboard page loads remain $O(\text{days})$ rather than $O(\text{submissions})$ without scanning raw submissions or answers tables.

### 4. Interactive Date Range Filters
The Analytics dashboard (`GET /analytics`) provides flexible date filtering while preserving default 90-day behavior:
- **Default Range**: Last 90 days (`range=90d`)
- **Available Presets**:
  - `Last 30 days` (`?range=30d`)
  - `Last 90 days` (`?range=90d`)
  - `Year to date` (`?range=ytd`): From January 1 of the current year through today
  - `All time` (`?range=all`): Entire customer history from earliest recorded submission
- **Custom Date Range**:
  - `?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`: Inclusive calendar date boundaries
  - Safe error handling: invalid date strings, inverted ranges (`start_date > end_date`), or missing dates cleanly fall back to the default 90-day window with an informative flash notice.

### 5. Historical Data Backfill Task
An idempotent rake task is provided to backfill or reconcile pre-aggregated metrics from raw historical submissions:

```bash
bin/rails analytics:backfill
```

Running this task multiple times is safe and produces identical metric counts with zero duplicate records.

---

## Public Endpoint Rate Limiting & Privacy

To protect public endpoints against automated form-spamming bots, ballot-box stuffing, and DoS attacks, the application incorporates Rails 8 native `ActionController::RateLimiting`:

### 1. Protected Endpoints & Configured Limits
- **Public Survey Viewing (`GET /s/:public_token`)**: Rate-limited to **60 requests/minute**.
- **Public Survey Submission (`POST /s/:public_token`)**: Rate-limited to **10 submissions/minute**.
- **Confirmation View (`GET /s/:public_token/success`)**: Rate-limited to **60 requests/minute**.

*Internal authenticated tenant routes (`/dashboard`, `/surveys`, `/analytics`) are not subject to these public limits.*

### 2. Scoped Rate-Limit Identity
Rate limits are scoped to the combination of client IP and survey token:

```ruby
rate_limit to: 10, within: 1.minute,
           by: -> { "#{request.remote_ip}:#{params[:public_token]}" },
           with: :render_rate_limited,
           only: :submit
```

This prevents cross-survey denial of service: if an abusive client reaches the limit on Survey A, legitimate traffic to Survey B is never throttled.

### 3. Durability & Multi-Instance Clustered Storage
In production, rate-limiting counters are backed by `SolidCache` (`config.cache_store = :solid_cache_store`), ensuring that rate limits are shared across multiple Puma processes or multi-instance container replicas.

### 4. Response & Privacy Safeguards
When a limit is exceeded:
- Responds with `HTTP 429 Too Many Requests`.
- Sets standard header `Retry-After: 60`.
- Renders responsive standalone `public/429.html` with informative guidance.
- **Privacy Guarantee**: Client IPs are only used temporarily within the cache TTL; no permanent IP tracking or respondent logging databases are retained.

---

## Bot Defense (Cloudflare Turnstile)

Public surveys can be protected against automated bots, credential stuffing, and spam attacks using **Cloudflare Turnstile**.

### 1. Configuration & Keys
Turnstile keys are configured via environment variables:
```bash
TURNSTILE_SITE_KEY=your-turnstile-site-key
TURNSTILE_SECRET_KEY=your-turnstile-secret-key
```
- **Local Development / Testing**: If `TURNSTILE_SECRET_KEY` is not set, CAPTCHA verification is safely bypassed, allowing developers and CI tests to run without external network dependencies.
- **Production**: When `TURNSTILE_SECRET_KEY` is present, `CaptchaVerifier.enabled?` evaluates to `true`, automatically injecting the Turnstile widget into public surveys and verifying tokens server-side.

### 2. Request Flow & Failure Behavior
- **Verification Service**: Handled by `CaptchaVerifier.verify(token, remote_ip:)`.
- **Fail Closed**: If Turnstile fails (e.g. invalid response, missing token, expired challenge, or network timeout), the submission is rejected (`HTTP 422`) with a user-friendly message (`"We couldn't verify that you're human. Please try again."`). Zero submission or answer records are created.
- **Rate-Limiting Coordination**: IP rate limiting executes before CAPTCHA verification, preventing attackers from flooding external verification endpoints.
- **Dashboard Isolation**: Customer dashboard actions (login, survey creation, editing) are never blocked by CAPTCHA.

---

## Device Response Limits (One Response Per Device)

Survey creators can optionally restrict submissions to **one response per device/browser** without requiring respondents to log in.

### 1. How It Works
- **Survey Creator Toggle**: In the survey builder under **Response Settings**, creators check *"Limit to one response per device/browser"*.
- **Default State**: Disabled by default (`limit_one_response_per_device: false`), preserving backwards compatibility for open public surveys.
- **Signed Cookie Mechanism**: When enabled, the application sets a tamper-proof Rails signed cookie (`cookies.signed[:survey_respondent_token]`) with a cryptographically secure token on first submission.
- **Database Unique Constraint**: A SHA-256 digest of the token scoped to the survey (`Digest::SHA256.hexdigest("#{survey.id}:#{token}")`) is stored on `submissions.respondent_token_digest`. A partial unique index (`index_submissions_on_survey_and_respondent_digest`) guarantees at the database level that concurrent race conditions from the same browser cannot create duplicate records.
- **Friendly Rejection**: If the same browser attempts to submit again, it is blocked with:
  > *"You have already submitted this survey from this browser."*

### 2. Privacy & Limitations
- **No Invasive Fingerprinting**: Does not collect canvas hashes, device serial numbers, or invasive telemetry.
- **Device vs. Person**: Clearing browser cookies or opening an incognito window resets the client token context. The feature is accurately described as *"one response per device/browser"* rather than *"one response per human"*.
- **Cross-Survey Independence**: A token issued for Survey A never blocks submission to Survey B.

---

## Testing

Run the full automated test suite:

```bash
bin/rails test
```

Test coverage includes:
- **Authentication**: Unauthenticated redirects, valid login, invalid login, logout session invalidation.
- **Tenant Isolation**: Cross-tenant URL tampering, unauthorized edits, cross-tenant submission access, isolated analytics.
- **Survey CRUD**: Creation with nested attributes, editing, deletion, and publication guards.
- **Public Surveys**: Public accessibility, draft survey 404 enforcement, text/number/multiple-choice inputs, required question validation, invalid option rejection.
- **Transactions**: Atomic rollback preventing partial submission creation.
- **Acceptance Tests**: Full end-to-end execution of Sections 42 and 43.

---

## Code Quality & Linting

Run RuboCop to verify style and formatting:

```bash
bundle exec rubocop
```

---

## Resetting the Environment

To reset the database and start fresh:

```bash
bin/rails db:drop
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

To stop and remove PostgreSQL Docker containers:

```bash
docker compose down -v
```
