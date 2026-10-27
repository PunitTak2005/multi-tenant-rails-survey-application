# Security Architecture & Threat Modeling

This document details the security defenses, threat mitigation strategies, and vulnerability assessment results across the application.

---

## 1. Security Architecture Summary

| Threat / Vulnerability Vector | Mitigation Mechanism | Implementation Status |
| :--- | :--- | :---: |
| **Credential Storage** | Salted BCrypt password hashing (`has_secure_password`). | **Implemented** |
| **Session Fixation** | `reset_session` executed on login and logout. | **Implemented** |
| **Cross-Tenant IDOR** | Hard customer scoping on all private queries (`current_customer.surveys...`). | **Implemented** |
| **Cross-Survey IDOR** | Two-level scoping (`@survey.submissions.find(params[:id])`). | **Implemented** |
| **Parameter Tampering** | Whitelisted Strong Parameters on all mutation endpoints. | **Implemented** |
| **SQL Injection (SQLi)** | Parameterized queries via ActiveRecord; explicit bind variables (`$1`, `$2`) in raw SQL UPSERTs. | **Implemented** |
| **Cross-Site Scripting (XSS)** | Default HTML escaping across all ERB templates; no unsafe `raw` or `html_safe` on user input. | **Implemented** |
| **Cross-Site Request Forgery (CSRF)**| `verify_authenticity_token` active across private and public forms. | **Implemented** |
| **Public Endpoint DoS / Spam** | Rails 8 ActionController `rate_limit` (60/min view, 10/min submit per IP + token). | **Implemented** |
| **Automated Bot Submissions** | Cloudflare Turnstile CAPTCHA verification (`CaptchaVerifier`). | **Implemented** |
| **Multiple Response Ballot Stuffing** | Signed HTTP-only client cookie (`cookies.signed`) + SHA256 digest + partial unique DB index. | **Implemented** |
| **Sequential ID Enumeration** | Unguessable 16-byte base64 cryptographic public tokens (`SecureRandom.urlsafe_base64`). | **Implemented** |
| **Two-Factor Authentication (2FA)** | Time-based One-Time Password (TOTP). | *Future Improvement* |
| **Role-Based Access Control (RBAC)**| Granular operator permissions (Admin vs Editor vs Viewer). | *Future Improvement* |

---

## 2. Threat Modeling & Mitigation Details

### A. Insecure Direct Object Reference (IDOR) & Cross-Tenant Data Leaks
- **Threat**: An authenticated operator belonging to Tenant A alters URL parameters (e.g. `/surveys/45` or `/surveys/12/submissions/88`) to access or modify records belonging to Tenant B.
- **Defense**:
  1. The application **never** queries private models through un-scoped global finders (e.g., `Survey.find(params[:id])` is strictly forbidden).
  2. All queries originate from `current_customer`:
     ```ruby
     @survey = current_customer.surveys.find(params[:id])
     ```
  3. Submissions enforce two-level scoping:
     ```ruby
     @survey = current_customer.surveys.find(params[:survey_id])
     @submission = @survey.submissions.find(params[:id])
     ```
  4. If the entity does not belong to the authenticated customer, PostgreSQL returns zero rows, raising `ActiveRecord::RecordNotFound`, gracefully caught and redirected with an alert.

### B. SQL Injection (SQLi)
- **Threat**: Malicious SQL fragments injected into form parameters or date filters.
- **Defense**:
  1. Standard queries use ActiveRecord relational methods (`where`, `find`, `find_by`), which generate parameterized SQL queries automatically.
  2. Raw SQL is utilized exclusively in two places (`SurveyDailyMetric.increment_response_count` and `analytics:backfill`). In both places, PostgreSQL **bind parameters** (`$1`, `$2`, `$3`) are strictly enforced via `ActiveRecord::Relation::QueryAttribute`:
     ```ruby
     binds = [
       ActiveRecord::Relation::QueryAttribute.new("survey_id", survey_id, ActiveRecord::Type::BigInteger.new),
       ActiveRecord::Relation::QueryAttribute.new("date", date, ActiveRecord::Type::Date.new)
     ]
     connection.exec_query(sql, "SurveyDailyMetric Increment", binds)
     ```

### C. Cross-Site Scripting (XSS)
- **Threat**: Attackers inject malicious JavaScript into survey titles, question prompts, or respondent text feedback.
- **Defense**:
  1. Rails ERB templates automatically escape all output expressions (`<%= ... %>`), converting `<`, `>`, `&`, `"`, and `'` into HTML entities.
  2. Custom answer display formatting (`Answer#display_value`) returns un-escaped plain strings, allowing ERB to safely escape text answers during page rendering.
  3. Static security audits via Brakeman inspect all template output bindings.

### D. Cross-Site Request Forgery (CSRF)
- **Threat**: A third-party malicious site tricks an authenticated operator's browser into submitting destructive requests (e.g. deleting a survey).
- **Defense**:
  1. `ActionController::Base` enforces CSRF authenticity tokens on all state-changing HTTP verbs (`POST`, `PUT`, `PATCH`, `DELETE`).
  2. Public submission forms include the CSRF authenticity token generated for that session.

### E. Rate Limiting on Public Endpoints
- **Threat**: Denial-of-Service (DoS) and rapid automated submission spam on unauthenticated endpoints `/s/:public_token`.
- **Defense**:
  1. `rate_limit to: 60, within: 1.minute` for viewing forms.
  2. `rate_limit to: 10, within: 1.minute` for submitting answers.
  3. Scoped by compound key `request.remote_ip:public_token`.
  4. Sends `Retry-After: 60` HTTP header and renders `429 Too Many Requests`.

### F. Ballot Stuffing & Multiple Response Prevention
- **Threat**: A respondent submits hundreds of responses to skew survey outcomes.
- **Defense**:
  1. Surveys support optional `limit_one_response_per_device: true`.
  2. The application assigns a signed, HTTP-only, 1-year cookie (`cookies.signed[:survey_respondent_token]`).
  3. A SHA256 digest `Digest::SHA256.hexdigest("#{survey_id}:#{token}")` is stored on the submission.
  4. A PostgreSQL **partial unique index** guarantees uniqueness at the database level:
     ```sql
     CREATE UNIQUE INDEX index_submissions_on_survey_and_respondent_digest
     ON submissions (survey_id, respondent_token_digest)
     WHERE (respondent_token_digest IS NOT NULL);
     ```
  5. Privacy-preserving: No IP address, browser fingerprint, or user tracking is stored.

---

## 3. Automated Security Audit Results

Static analysis and dependency auditing are executed regularly:

### A. Brakeman Static Analysis
```text
== Overview ==
Controllers: 7
Models: 9
Templates: 14
Errors: 0
Security Warnings: 0

== Warning Types ==
No warnings found
```

### B. Bundler Audit (CVE Database)
```text
No vulnerabilities found
```

---

## 4. Distinguishing Implemented vs. Future Improvements

### Implemented Controls:
- BCrypt salted hashing
- Session fixation protection (`reset_session`)
- Multi-tenant customer query scoping
- Two-level submission IDOR protection
- Strong Parameters
- Parameterized SQL & Bind attributes
- HTML auto-escaping
- CSRF protection
- Rails 8 IP rate limiting
- Cloudflare Turnstile CAPTCHA
- Signed cookie device limitation with partial unique index
- Unguessable cryptographic public tokens

### Future Production Improvements:
- **Two-Factor Authentication (2FA)**: Requiring TOTP via Google Authenticator / Authy for operator logins.
- **Role-Based Access Control (RBAC)**: Supporting multiple operator roles per tenant (e.g. `Owner`, `Editor`, `Analyst`).
- **Audit Logging**: Immutable audit trail tracking survey creation, modification, and deletion events with IP and timestamp.
- **Content Security Policy (CSP)**: Strict headers restricting external script and font sources.

---

## 5. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Authentication & Authorization](AUTHENTICATION_AND_AUTHORIZATION.md)
- [Public Submission Flow](PUBLIC_SUBMISSION_FLOW.md)
- [Database Design](DATABASE_DESIGN.md)
