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

Generate realistic seed data featuring 2 separate customer tenants, users, surveys, questions, and historical submissions distributed across the last 90 days:

```bash
bin/rails db:seed
```

### 6. Create or Provision Initial Customer Admin (Rake Task)

You can also provision a fresh customer and administrative user via environment variables:

```bash
INITIAL_CUSTOMER_NAME="Acme Inc" \
INITIAL_USER_EMAIL="admin@acme.test" \
INITIAL_USER_PASSWORD="ChangeMe123!" \
bin/rails customers:create_initial
```

This task safely idempotently creates or updates the user and prints the login credentials to stdout.

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
- **Includes**: 3 surveys (2 published, 1 draft), multiple questions, and 125+ historical submissions.

### Customer Tenant B (Beta Technologies)
- **Login URL**: `http://localhost:3000/login`
- **Email**: `beta_admin@beta.test`
- **Password**: `ChangeMe123!`
- **Includes**: 1 survey and isolated submissions.

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

### 4. Historical Data Backfill Task
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
