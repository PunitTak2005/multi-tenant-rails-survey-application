# System Architecture & Technical Overview

This document provides a comprehensive architectural breakdown of the **Multi-Tenant B2B SaaS Survey Application**, detailing runtime components, design patterns, tenant isolation boundaries, and data pipelines.

---

## 1. High-Level Technology Stack

| Layer | Technology | Details / Version |
| :--- | :--- | :--- |
| **Language Runtime** | Ruby | `3.3.6` (RVM managed, YJIT enabled) |
| **Web Framework** | Ruby on Rails | `8.1.4` (MVC, ActiveRecord, ActionPack, ActiveJob) |
| **Relational Database** | PostgreSQL | `16.x` running via Docker Compose (`multi_tenant_development`, `multi_tenant_test`) |
| **Authentication** | BCrypt / Rails Native | `has_secure_password`, session fixation defense, signed HTTP-only cookies |
| **Frontend / Assets** | Propshaft & Importmaps | Modern HTML5/CSS3, Turbo 8, Stimulus JS controllers (No Node/Webpack build step) |
| **Pagination** | Pagy | `v9.3.3` (high-performance, low-memory offset pagination) |
| **Background Processing**| ActiveJob | `UpdateSurveyDailyMetricJob` (asynchronous aggregation pipeline) |
| **Security & Quality** | Brakeman, RuboCop, Bundler-Audit | Static security analysis, linting, dependency vulnerability auditing |

---

## 2. Request & Component Flow Architecture

```
                                  [ Incoming Client Request ]
                                               │
                                               ▼
                                      [ Rack / Puma 8.0 ]
                                               │
                                               ▼
                                     [ Rails Router (routes.rb) ]
                                               │
                       ┌───────────────────────┴───────────────────────┐
                       │                                               │
                 [ Private Route ]                               [ Public Route ]
                       │                                               │
                       ▼                                               ▼
             [ Authenticate User! ]                          [ IP Rate Limiting ]
        (Validates session[:user_id])                 (60/min show, 10/min submit)
                       │                                               │
                       ▼                                               ▼
            [ Hard Tenant Scoping ]                          [ Bot / Captcha Defense ]
         (current_customer.surveys...)                 (Cloudflare Turnstile Check)
                       │                                               │
                       ▼                                               ▼
          [ Controllers & Services ]                        [ SubmitSurvey Service ]
        (Surveys, Submissions, Analytics)              (ActiveRecord::Base.transaction)
                       │                                               │
                       └───────────────────────┬───────────────────────┘
                                               │
                                               ▼
                                     [ ActiveRecord Models ]
                              (Validation, Callbacks, Associations)
                                               │
                                               ▼
                                   [ PostgreSQL 16 Database ]
                           (Normalized Tables, Foreign Keys, Indexes)
                                               │
                                               ▼
                                   [ Background Processing ]
                                (UpdateSurveyDailyMetricJob)
                                               │
                                               ▼
                               [ survey_daily_metrics (UPSERT) ]
```

---

## 3. Core Architectural Patterns

### A. Strict Multi-Tenant Scoping (Shared Database, Separate Schemas via Foreign Keys)
The application implements **logical multi-tenancy** within a shared PostgreSQL database. Every business entity is rooted in the `customers` table.

- **Tenant Root**: `Customer` represents an organization.
- **Tenant Scope Enforcement**: Authenticated controller queries never read or modify data via un-scoped lookups (e.g., `Survey.find(params[:id])` is strictly disallowed). Instead, queries flow through the authenticated tenant session:
  ```ruby
  # In ApplicationController
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_customer
    @current_customer ||= current_user&.customer
  end

  # In SurveysController / SubmissionsController
  @survey = current_customer.surveys.find(params[:id])
  @submissions = @survey.submissions.find(params[:id])
  ```
- **Inherent IDOR Protection**: If Tenant A attempts to access Tenant B's survey or submission by guessing an ID, ActiveRecord raises `ActiveRecord::RecordNotFound`, gracefully caught and redirected without leaking data existence.

### B. Service Object Pattern (`SubmitSurvey`)
Complex business logic that coordinates multiple database models is extracted from controllers into focused, testable service objects.
- **Location**: `app/services/submit_survey.rb`
- **Responsibility**: Coordinates public respondent answers, performs validation against survey question types, checks device submission limits, and persists the `Submission` and `Answer` records inside an atomic `ActiveRecord::Base.transaction`.
- **Interface**: Returns a lightweight `Result` struct (`success?`, `submission`, `errors`), keeping the `PublicSurveysController` thin and free of transaction logic.

### C. Bot & Captcha Verification (`CaptchaVerifier`)
- **Location**: `app/services/captcha_verifier.rb`
- **Responsibility**: Verifies Cloudflare Turnstile tokens via external HTTP POST verification while providing environment toggles and test mock harnesses (`CaptchaVerifier.with_mock`).

### D. Asynchronous Pre-Aggregated Analytics Pipeline
To prevent database CPU exhaustion on high-volume datasets (e.g. millions of raw submissions), the application decouples analytics reporting from raw submission scans:
1. When a submission is committed (`after_commit on: :create` in `Submission`), it enqueues `UpdateSurveyDailyMetricJob`.
2. The job triggers an **atomic PostgreSQL UPSERT** in `SurveyDailyMetric.increment_response_count(survey_id, date)`.
3. The `AnalyticsController` reads directly from `survey_daily_metrics`, executing queries in $O(\text{days})$ time rather than $O(\text{submissions})$.

### E. Stimulus JS Controller for Dynamic Nested Attributes
- **Location**: `app/javascript/controllers/survey_builder_controller.js`
- **Responsibility**: Dynamically adds and removes questions and multiple-choice options on the client side using HTML `<template>` tags without requiring page reloads or external JavaScript build steps.

---

## 4. Multi-Tenant Domain Boundary Diagram

```text
+-------------------------------------------------------------------------------+
| Customer Tenant A (Acme Corporation, id: 10)                                  |
|                                                                               |
|   ├── User: admin@acme.test (customer_id: 10)                                 |
|   │                                                                           |
|   └── Surveys (customer_id: 10)                                               |
|         ├── Survey 17: "Customer Satisfaction Survey"                         |
|         │     ├── Questions (position: 1..3)                                  |
|         │     │     └── QuestionOptions (Very satisfied, Satisfied, etc.)    |
|         │     ├── Submissions (130 sessions)                                  |
|         │     │     └── Answers (349 typed records)                           |
|         │     └── DailyMetrics (50 pre-aggregated date rows)                  |
|         │                                                                     |
|         └── Survey 18: "Product Feature Evaluation"                           |
|               └── Submissions (10 sessions)                                   |
+-------------------------------------------------------------------------------+
                                    ║
                 STRICT DATABASE FOREIGN KEY & QUERY BOUNDARY
                 (No cross-tenant joins or parameter leaks)
                                    ║
+-------------------------------------------------------------------------------+
| Customer Tenant B (Beta Technologies, id: 11)                                 |
|                                                                               |
|   ├── User: beta_admin@beta.test (customer_id: 11)                            |
|   │                                                                           |
|   └── Surveys (customer_id: 11)                                               |
|         └── Survey 20: "Beta Platform Onboarding Survey"                      |
|               ├── Questions (position: 1..2)                                  |
|               ├── Submissions (17 sessions)                                   |
|               └── DailyMetrics (17 pre-aggregated date rows)                  |
+-------------------------------------------------------------------------------+
```

---

## 5. Architectural Trade-offs & Design Rationale

### Shared Database vs. Separate Databases / Schemas
- **Chosen Approach**: Shared PostgreSQL database with `customer_id` foreign key columns and application-enforced scoping.
- **Why**: Drastically lower infrastructure complexity, seamless automated database migrations (`bin/rails db:migrate`), low operational overhead for small-to-midsize SaaS platforms, and straightforward cross-tenant reporting for platform owners.
- **Trade-off**: Requires strict developer discipline to always scope queries through `current_customer`. (Mitigated in this app by comprehensive automated model, controller, and integration tests).

### Normalized Answers vs. PostgreSQL JSONB Document Storage
- **Chosen Approach**: Fully normalized `submissions` and `answers` tables with typed value columns (`text_value`, `number_value`, `selected_option_id`).
- **Why**: Database-enforced referential integrity (`FOREIGN KEY ... ON DELETE CASCADE`), strict SQL typing, numeric calculation support (`AVG`, `SUM`, `MIN`, `MAX`), and prevention of invalid choice references.
- **Trade-off**: Requires joining tables when retrieving a full submission with questions and options. (Mitigated through eager loading: `includes(answers: %i[question selected_option])`).

---

## 6. Related Documentation
- [Application Flow & Request Lifecycle](APPLICATION_FLOW.md)
- [Database Schema & Design Defense](DATABASE_DESIGN.md)
- [Class & Code Guide](CLASS_AND_CODE_GUIDE.md)
- [Security Architecture](SECURITY.md)
