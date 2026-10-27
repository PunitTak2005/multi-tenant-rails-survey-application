# Project Cheat Sheet & Quick Reference

A fast-lookup, single-document reference designed for immediate review before an interview, demo, or code evaluation.

---

## 1. Tech Stack At-a-Glance

- **Language / Runtime**: Ruby `3.3.6` (RVM)
- **Framework**: Ruby on Rails `8.1.4`
- **Database**: PostgreSQL `16.x` via Docker Compose
- **Frontend / Assets**: Propshaft, Importmaps, Stimulus JS, Turbo 8, Modern CSS3
- **Security / Hashing**: BCrypt, Signed Cookies, Cloudflare Turnstile CAPTCHA
- **Pagination**: Pagy `9.3.3`
- **Testing**: Minitest, Capybara, Selenium WebDriver, Headless Google Chrome
- **Code Quality**: RuboCop (0 offenses), Brakeman (0 warnings), Bundler Audit (0 CVEs)

---

## 2. Essential Commands

### Development Server & Environment
```bash
# Start PostgreSQL container
docker compose up -d

# Start Rails Puma server
bin/rails server -b 0.0.0.0 -p 3000

# Open interactive Rails console
bin/rails console
```

### Database & Seed Tasks
```bash
# Prepare database
bin/rails db:create db:migrate

# Seed realistic deterministic data (~3 months historical responses)
bin/rails db:seed

# Dual-tenant quick provisioning
bin/rails customers:setup

# Backfill pre-aggregated daily metrics from raw submissions
bin/rails analytics:backfill
```

### Automated Testing & Quality Scans
```bash
# Run unit & integration test suite (192 tests)
bin/rails test

# Run seed data test suite specifically
bin/rails test test/models/seed_data_test.rb

# Run system browser tests in headless Chrome (6 tests)
bin/rails test:system

# Code style linting
bundle exec rubocop

# Security vulnerability scan
bundle exec brakeman -q

# Gem vulnerability audit
bundle exec bundle-audit check
```

---

## 3. Core Route Map

| Method | Path | Controller#Action | Auth? | Purpose |
| :--- | :--- | :--- | :---: | :--- |
| `GET` | `/login` | `sessions#new` | No | Login form |
| `POST` | `/login` | `sessions#create` | No | Authenticates user & resets session |
| `DELETE` | `/logout` | `sessions#destroy` | Yes | Destroys session |
| `GET` | `/dashboard` | `dashboard#index` | Yes | Tenant dashboard overview |
| `GET` | `/surveys` | `surveys#index` | Yes | Lists customer surveys |
| `POST` | `/surveys` | `surveys#create` | Yes | Creates survey with nested questions |
| `GET` | `/surveys/:id` | `surveys#show` | Yes | Shows survey details & public link |
| `POST` | `/surveys/:id/publish` | `surveys#publish` | Yes | Validates & publishes survey |
| `GET` | `/surveys/:survey_id/submissions` | `submissions#index` | Yes | Paginated submissions list (Pagy) |
| `GET` | `/surveys/:survey_id/submissions/:id` | `submissions#show` | Yes | Individual response answer breakdown |
| `GET` | `/analytics` | `analytics#index` | Yes | 90-day / custom daily response metrics |
| `GET` | `/s/:public_token` | `public_surveys#show` | No | Public survey response form |
| `POST` | `/s/:public_token` | `public_surveys#submit` | No | Submits respondent answers (transactional) |
| `GET` | `/s/:public_token/success` | `public_surveys#success` | No | Submission confirmation page |

---

## 4. Database Relationship Hierarchy

```text
Customer (1)
  ├── User (N)
  └── Survey (N)
        ├── Question (N)
        │     └── QuestionOption (N)
        ├── Submission (N)
        │     └── Answer (N) [belongs_to :question, optional: :selected_option]
        └── SurveyDailyMetric (N) [unique on survey_id + date]
```

---

## 5. Demo Credentials (From Seeds)

| Tenant | Email | Password | Seeded Content |
| :--- | :--- | :--- | :--- |
| **Acme Corporation** | `admin@acme.test` | `ChangeMe123!` | 3 surveys (2 published, 1 draft), 140 submissions spanning ~3 months |
| **Beta Technologies**| `beta_admin@beta.test` | `ChangeMe123!` | 1 published survey, 17 submissions isolated to Beta |

---

## 6. Key Security Mechanisms Summary

1. **Authentication**: `has_secure_password` (BCrypt), `reset_session` on login/logout.
2. **Tenant Scoping**: All queries route through `current_customer` (IDOR defense).
3. **Submission Scoping**: Two-level scoping (`current_customer` -> `@survey` -> `@submissions`).
4. **Strong Parameters**: Whitelisted parameters prevent mass-assignment vulnerabilities.
5. **SQL Injection Defense**: Parameterized queries + bind variables (`$1`, `$2`) in raw SQL.
6. **XSS Defense**: Default HTML escaping in ERB.
7. **Rate Limiting**: ActionController `rate_limit` (60/min view, 10/min submit per IP + token).
8. **Bot Defense**: Cloudflare Turnstile CAPTCHA verification (`CaptchaVerifier`).
9. **Ballot Stuffing Defense**: Signed HTTP-only cookie + SHA256 digest + partial unique DB index.
10. **Public Tokens**: 16-byte cryptographic random base64 strings (`SecureRandom.urlsafe_base64`).
