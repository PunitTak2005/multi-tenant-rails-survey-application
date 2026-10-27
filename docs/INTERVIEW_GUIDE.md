# Interview & Technical Evaluation Guide

This guide provides technically rigorous, direct answers to common architectural, design, and code-level questions about this application. Use this document when preparing for technical interviews, system design discussions, or code evaluations.

---

### 1. What is this project?
> "It is a production-quality, multi-tenant B2B SaaS survey platform built with Ruby on Rails 8 and PostgreSQL 16. It enables organizations (tenants) to manage survey creators, build dynamic surveys with multiple typed question formats (Text, Number, Multiple Choice), publish them via secure public URLs, and collect anonymous responses at scale with instantaneous, pre-aggregated analytics and strict tenant isolation."

---

### 2. Why did you choose Rails?
> "Rails 8 provides a cohesive, mature MVC framework with ActiveRecord for relational modeling, built-in secure password management (`has_secure_password`), transactional integrity, native ActionController rate limiting, and modern asset management via Propshaft and Importmaps without Node/Webpack bloat. It allows us to build robust, secure, and maintainable software quickly while adhering to convention over configuration."

---

### 3. How does multi-tenancy work in this application?
> "We implement logical multi-tenancy using a shared database with tenant-scoped foreign keys. The root entity is `Customer`. All private application models (`User`, `Survey`, `Submission`, `SurveyDailyMetric`) belong directly or indirectly to a `Customer`. The application enforces tenant boundaries at the query level by always scoping database reads and writes through `current_customer` (e.g. `current_customer.surveys.find(params[:id])`), completely eliminating cross-tenant data leaks."

---

### 4. How does authentication work?
> "Authentication is built using Rails' native `has_secure_password` backed by BCrypt. The `User` model stores a salted `password_digest`. When an operator posts credentials to `SessionsController#create`, the password is authenticated, `reset_session` is called to prevent session fixation attacks, and the user's ID is stored in a cryptographically signed HTTP-only cookie session."

---

### 5. How does survey creation work?
> "Surveys are created through a dynamic form powered by Rails nested attributes and a Stimulus JS controller (`survey_builder_controller.js`). Operators can dynamically add and remove questions and multiple-choice options on the client side without page reloads. When submitted, `SurveysController#create` permits the nested parameter tree and persists the survey, questions, and options in a single database transaction. Surveys default to `draft` status."

---

### 6. How are questions modeled?
> "Questions are normalized into a dedicated `questions` table linked to `surveys` via foreign key `survey_id`. Each question stores `question_text`, an integer enum `question_type` (`0: text`, `1: number`, `2: multiple_choice`), a 1-based `position` integer for ordering, and a boolean `required` flag. Multiple-choice questions have associated `question_options` rows. Model validations prevent non-multiple-choice questions from having options."

---

### 7. How are answers stored?
> "Answers are stored in a normalized `answers` table linked to both a `submission` and a `question`. Rather than using a generic string column or JSON blob, the table provides typed value columns:
> - `text_value` (`text`) for text questions
> - `number_value` (`decimal(15, 2)`) for numeric questions
> - `selected_option_id` (`bigint`, foreign key -> `question_options.id`) for multiple-choice questions
> Model validations strictly enforce that only the column corresponding to the question type is populated."

---

### 8. How does public submission work without login?
> "When a survey is published, it is assigned a cryptographic 16-byte token (`public_token`). Anonymous respondents visit `/s/:public_token`. The `PublicSurveysController` requires no authentication, verifies the survey is published, enforces IP rate limiting (60/min view, 10/min submit), checks Cloudflare Turnstile CAPTCHA, verifies device cookie restrictions, and passes the parameters to the `SubmitSurvey` service object, which persists the submission and answers atomically."

---

### 9. How do you prevent one customer from accessing another customer's data (IDOR)?
> "We prevent Insecure Direct Object References (IDOR) by forbidding global, un-scoped queries such as `Survey.find(params[:id])`. Every private controller action scopes queries through `current_customer`:
> ```ruby
> @survey = current_customer.surveys.find(params[:id])
> ```
> For submissions, we apply two-level scoping:
> ```ruby
> @survey = current_customer.surveys.find(params[:survey_id])
> @submission = @survey.submissions.find(params[:id])
> ```
> If an operator attempts to access an entity belonging to another customer or survey, PostgreSQL returns 0 rows, ActiveRecord raises `ActiveRecord::RecordNotFound`, and the user is safely redirected."

---

### 10. How does analytics work?
> "Analytics reporting is decoupled from raw submission table scans. When a submission is committed, an ActiveJob (`UpdateSurveyDailyMetricJob`) enqueues and executes a concurrency-safe atomic PostgreSQL UPSERT on `survey_daily_metrics`. When an operator opens `/analytics`, the controller reads pre-aggregated daily counts within the selected window (`30d`, `90d`, `ytd`, `all`, or custom), calculating totals, daily averages, active days, peak days, and per-survey breakdowns in under 2ms."

---

### 11. Why is the database normalized?
> "Normalization enforces 1NF (atomic columns), 2NF (full key dependence), and 3NF (no transitive dependencies). It ensures referential integrity via PostgreSQL foreign keys, eliminates data redundancy, enables native database indexing on options and questions, supports exact SQL mathematical functions on numbers without casting, and prevents data corruption."

---

### 12. Why not store the entire survey or answers as JSON?
> "While JSON/JSONB is flexible, storing answers as JSON sacrifices relational foreign keys, allows invalid option IDs to be inserted without database detection, prevents type-safe numeric SQL aggregations (`AVG`, `SUM`, `MIN`, `MAX`) without runtime casting, requires expensive JSON parsing or GIN indexing, and makes cascade deletions complex."

---

### 13. Why are answers separate from submissions?
> "A submission represents a single respondent's completion session at a specific point in time. Answers represent the individual, discrete data points for each question. Separating them allows:
> - Individual question validation
> - Foreign key linkage to specific `questions` and `question_options`
> - Direct aggregation across all answers to a specific question (e.g. calculating the average rating for Question 3 across all submissions)
> - Clean handling of optional questions that were skipped"

---

### 14. How does the application scale?
> "1. **Database Decoupling**: Analytics reads from pre-aggregated `survey_daily_metrics` ($O(\text{days})$ rather than $O(\text{submissions})$).
> 2. **Asynchronous Jobs**: Metric counter increments run via ActiveJob workers outside the HTTP request.
> 3. **Pagination**: Submissions are paginated via Pagy 9 with a maximum limit of 100 rows per page.
> 4. **Eager Loading**: `includes(answers: %i[question selected_option])` eliminates N+1 queries.
> 5. **Indexing**: B-Tree composite indexes cover tenant lookups, public token lookups, and submission timestamps."

---

### 15. What indexes are used and why?
> "- `users[email]` (UNIQUE): Fast login lookup and uniqueness enforcement.
> - `surveys[public_token]` (UNIQUE): Instant lookup for public survey URLs.
> - `surveys[customer_id, status]` & `surveys[customer_id, created_at]`: Tenant-scoped dashboard counts and recent survey lists.
> - `questions[survey_id, position]`: Ordered question retrieval for survey forms.
> - `submissions[survey_id, submitted_at]`: Submissions pagination and sorting.
> - `submissions[survey_id, respondent_token_digest]` (PARTIAL UNIQUE): Device submission uniqueness without indexing nulls.
> - `survey_daily_metrics[survey_id, date]` (UNIQUE): Concurrency-safe atomic UPSERT target."

---

### 16. Why are daily metrics useful?
> "They provide an architectural buffer against read-heavy dashboard loads. Instead of scanning 1,000,000 submission rows on every dashboard refresh, the database reads at most 90 rows for a 90-day chart. This protects the primary database from CPU exhaustion and keeps dashboard latency under 2ms."

---

### 17. How does seed data work?
> "The seed file `db/seeds.rb` uses foreign-key cascade order deletion (`delete_all`) to ensure idempotency. It uses a dedicated, isolated PRNG (`Random.new(42)`) to ensure 100% deterministic, repeatable data across runs. It provisions 2 customer tenants, 2 users, 4 surveys, 7 questions, 10 options, 157 historical submissions spanning 89 days (~3 months), 403 typed answers, and 77 synchronized daily metric records via `analytics:backfill`."

---

### 18. What security measures exist?
> "- BCrypt password hashing (`has_secure_password`)
> - Session fixation protection (`reset_session`)
> - Tenant-scoped query traversal (IDOR defense)
> - Two-level submission scoping (cross-survey IDOR defense)
> - Strong Parameters
> - Parameterized SQL queries & bind parameters (SQLi defense)
> - Default ERB HTML escaping (XSS defense)
> - CSRF authenticity tokens
> - ActionController IP rate limiting (DoS/spam defense)
> - Cloudflare Turnstile bot verification
> - Signed HTTP-only cookie device restrictions
> - Unguessable 16-byte base64 public tokens"

---

### 19. What would you improve in the future?
> "- **Two-Factor Authentication (2FA/TOTP)** for operator accounts.
> - **Role-Based Access Control (RBAC)** allowing organizations to invite multiple operators with granular roles (`Admin`, `Editor`, `Analyst`).
> - **Survey Question Logic (Branching / Skip Logic)**: Dynamically skipping questions based on previous multiple-choice selections.
> - **Export Pipeline**: Background worker generating CSV / Excel exports of survey submissions stored in S3.
> - **Read Replica Routing**: Offloading heavy analytical reporting to a PostgreSQL read replica."
