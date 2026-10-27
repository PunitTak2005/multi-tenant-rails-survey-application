# Authentication & Authorization Architecture

This document provides a thorough explanation of the security boundaries, authentication mechanisms, and multi-tenant authorization strategies implemented in the application.

---

## 1. Authentication vs. Authorization

It is critical to distinguish between these two distinct security concerns:

| Dimension | Authentication ("Who are you?") | Authorization / Tenant Scoping ("What can you access?") |
| :--- | :--- | :--- |
| **Question Answered** | *"Are you a valid operator with verified credentials?"* | *"Does the data you are requesting belong to your organization?"* |
| **Mechanisms** | BCrypt password hashing, session cookies, `authenticate_user!`. | Scoped ActiveRecord queries (`current_customer.surveys...`). |
| **Primary Risk** | Credential stuffing, brute force, session fixation. | Insecure Direct Object References (IDOR), cross-tenant data leaks. |
| **Code Location** | `SessionsController`, `User#has_secure_password`. | `ApplicationController#current_customer`, controller `set_survey` filters. |

---

## 2. Authentication Implementation Details

### A. Password Storage & BCrypt Hashing
Passwords are never stored in plain text. The application uses Rails' built-in `has_secure_password` backed by the `bcrypt` gem:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  belongs_to :customer
  has_secure_password
  ...
end
```
- **Password Salting**: BCrypt automatically generates a cryptographic salt per user, preventing precomputed rainbow table attacks.
- **Cost Factor**: Configured to standard cryptographic work factors, ensuring brute-force resistance without noticeable operator login latency.
- **Database Column**: Stored in the `users.password_digest` varchar column.

### B. Email Normalization
To prevent duplicate account creation or login failures caused by case sensitivity or leading/trailing whitespace, `User` uses Rails 7.1+ normalization:
```ruby
normalizes :email, with: ->(email) { email.to_s.strip.downcase }
```

### C. Session Management & Session Fixation Protection
In `SessionsController#create`, when password authentication succeeds, `reset_session` is called immediately before assigning the user ID:
```ruby
# app/controllers/sessions_controller.rb
def create
  user = User.find_by(email: params[:email]&.to_s&.strip&.downcase)

  if user&.authenticate(params[:password])
    reset_session # Critical: Destroys old session ID to prevent fixation
    session[:user_id] = user.id
    flash[:notice] = "Welcome back, #{user.name}!"
    redirect_to dashboard_path
  else
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_entity
  end
end
```
- **Why `reset_session` is vital**: If an attacker primes an unauthenticated browser with a known session ID, calling `reset_session` upon authentication forces Rails to allocate a new cryptographic session key, neutralizing session fixation attacks.

### D. Logout & Session Invalidation
When an operator logs out (`DELETE /logout`), `reset_session` purges all session variables:
```ruby
def destroy
  reset_session
  flash[:notice] = "You have been logged out successfully."
  redirect_to login_path
end
```

---

## 3. Authorization & Multi-Tenant Scoping (IDOR Prevention)

### The Danger of Un-Scoped Lookups
In single-tenant or poorly scoped multi-tenant apps, developers often write:
```ruby
# VULNERABLE TO IDOR:
@survey = Survey.find(params[:id])
@submission = Submission.find(params[:id])
```
If User 1 (from Customer A) inspects their survey `/surveys/42` and changes the URL to `/surveys/43`, an un-scoped `find` loads Customer B's survey. This is an **Insecure Direct Object Reference (IDOR)** vulnerability.

### The Solution: Tenant-Scoped Query Traversal
In this application, **no private controller ever queries `Survey` directly**. All private queries traverse through the authenticated session's `current_customer`:

```ruby
# app/controllers/application_controller.rb
def current_user
  @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
end

def current_customer
  @current_customer ||= current_user&.customer
end
```

In `SurveysController`:
```ruby
def set_survey
  @survey = current_customer.surveys.find(params[:id])
rescue ActiveRecord::RecordNotFound
  redirect_to surveys_path, alert: "Survey not found."
end
```
- **Result**: PostgreSQL executes:
  ```sql
  SELECT * FROM "surveys" WHERE "surveys"."customer_id" = 10 AND "surveys"."id" = 43 LIMIT 1;
  ```
  If survey 43 belongs to customer 11, the query returns 0 rows, ActiveRecord raises `ActiveRecord::RecordNotFound`, and the application safely redirects without disclosing that survey 43 even exists.

### Two-Level Scoping for Submissions
In `SubmissionsController`, the application enforces two distinct security boundaries:
1. **Tenant Boundary**: The survey must belong to `current_customer`.
2. **Survey Boundary**: The submission must belong to that specific `@survey`.

```ruby
# app/controllers/submissions_controller.rb
def set_survey
  @survey = current_customer.surveys.find(params[:survey_id])
rescue ActiveRecord::RecordNotFound
  redirect_to surveys_path, alert: "Survey not found."
end

def show
  @submission = @survey.submissions.find(params[:id])
  ...
rescue ActiveRecord::RecordNotFound
  redirect_to survey_submissions_path(@survey), alert: "Submission not found."
end
```
This guarantees:
- Customer A cannot view Customer B's submissions.
- Customer A cannot view submissions from Survey 1 when requesting Survey 2 (cross-survey IDOR).

---

## 4. Public vs. Private Route Matrix

| Route | Classification | Authentication Required? | Security Controls Enforced |
| :--- | :---: | :---: | :--- |
| `GET /login` | **Public** | No | Redirects to dashboard if already authenticated. |
| `POST /login` | **Public** | No | BCrypt timing-safe comparison, `reset_session`. |
| `DELETE /logout` | **Private** | Yes | Purges session state via `reset_session`. |
| `GET /dashboard` | **Private** | Yes | `before_action :authenticate_user!`, scoped to `current_customer`. |
| `GET /surveys` | **Private** | Yes | Scoped to `current_customer.surveys`. |
| `POST /surveys` | **Private** | Yes | Built via `current_customer.surveys.build`, Strong Parameters. |
| `GET /surveys/:id` | **Private** | Yes | Scoped to `current_customer.surveys.find(params[:id])`. |
| `POST /surveys/:id/publish` | **Private** | Yes | Scoped to `current_customer.surveys`, question completeness check. |
| `GET /surveys/:survey_id/submissions` | **Private** | Yes | Two-level scoping (`current_customer` -> `@survey` -> `@submissions`). |
| `GET /surveys/:survey_id/submissions/:id` | **Private** | Yes | Two-level scoping, eager loaded to prevent N+1. |
| `GET /analytics` | **Private** | Yes | Scoped to `current_customer.survey_daily_metrics`. |
| `GET /s/:public_token` | **Public** | No | IP rate limiting (60/min), unguessable token lookup, published status. |
| `POST /s/:public_token` | **Public** | No | IP rate limiting (10/min), Turnstile CAPTCHA, signed cookie limit, atomic transaction. |
| `GET /s/:public_token/success` | **Public** | No | Rate limited, published status check. |

---

## 5. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Public Submission Flow](PUBLIC_SUBMISSION_FLOW.md)
- [Database Design](DATABASE_DESIGN.md)
- [Security Architecture](SECURITY.md)
