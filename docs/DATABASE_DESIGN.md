# Database & Multi-Tenancy Architecture Design

This document details the relational database schema, tenant isolation strategy, and future analytics architecture for the **Multi-Tenant Survey SaaS Application**.

---

## 1. Entity Relationship Diagram (ERD)

```text
Customer (Tenant Boundary)
  │
  ├── Users (Customer-scoped authentication)
  │
  └── Surveys (Customer-scoped survey management)
        │
        ├── Questions (Deterministic ordering via `position`)
        │     │
        │     └── QuestionOptions (For multiple-choice questions)
        │
        └── Submissions (Anonymous public response sessions)
              │
              └── Answers (Normalized responses linked to Question & Submission)
```

---

## 2. Relational Schema Specifications

### `customers`
Represents the organizational tenant. All private SaaS entities belong directly or indirectly to a customer record.
- `id` (bigserial, primary key)
- `name` (varchar, NOT NULL): Company or organization name.
- `created_at`, `updated_at` (timestamps)

### `users`
Authenticated operators belonging strictly to a customer.
- `id` (bigserial, primary key)
- `customer_id` (bigint, NOT NULL, FK -> `customers.id` ON DELETE CASCADE)
- `email` (varchar, NOT NULL, UNIQUE INDEX): Normalized lowercase email address.
- `password_digest` (varchar, NOT NULL): BCrypt hashed password.
- `name` (varchar, NOT NULL): Display name of user.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[email]` (unique), `[customer_id]`

### `surveys`
Surveys created and owned by customer tenants.
- `id` (bigserial, primary key)
- `customer_id` (bigint, NOT NULL, FK -> `customers.id` ON DELETE CASCADE)
- `title` (varchar, NOT NULL): Human-readable survey title.
- `description` (text): Purpose or instructions displayed to respondents.
- `status` (integer, NOT NULL, default: 0): Enum (`0: draft`, `1: published`).
- `public_token` (varchar, NOT NULL, UNIQUE INDEX): Secure, unpredictable random token (e.g. `XaygLIkiwnYCvgGDzp4hqw`) used in the public submission URL `/s/:public_token`. Internal serial IDs are never exposed publicly.
- `published_at` (timestamp): Timestamp when survey status transitioned to published.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[public_token]` (unique), `[customer_id]`, `[customer_id, status]`, `[customer_id, created_at]`

### `questions`
Ordered questions configured within a survey.
- `id` (bigserial, primary key)
- `survey_id` (bigint, NOT NULL, FK -> `surveys.id` ON DELETE CASCADE)
- `question_text` (text, NOT NULL): The prompt shown to respondents.
- `question_type` (integer, NOT NULL, default: 0): Enum (`0: text`, `1: number`, `2: multiple_choice`).
- `position` (integer, NOT NULL, default: 1): 1-based order index.
- `required` (boolean, NOT NULL, default: false): Enforces response requirement upon submission.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[survey_id]`, `[survey_id, position]`

### `question_options`
Selectable choices for multiple-choice questions.
- `id` (bigserial, primary key)
- `question_id` (bigint, NOT NULL, FK -> `questions.id` ON DELETE CASCADE)
- `label` (varchar, NOT NULL): Text label of option (e.g. "Very satisfied").
- `position` (integer, NOT NULL, default: 1): Display order.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[question_id]`, `[question_id, position]`

### `submissions`
Session record representing a single completed response to a published survey. Anonymous submissions do not require authentication.
- `id` (bigserial, primary key)
- `survey_id` (bigint, NOT NULL, FK -> `surveys.id` ON DELETE CASCADE)
- `submitted_at` (timestamp, NOT NULL): Exact completion time.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[survey_id]`, `[survey_id, submitted_at]`, `[submitted_at]`

### `answers`
Discrete, typed response values linked to both a `submission` and a specific `question`.
- `id` (bigserial, primary key)
- `submission_id` (bigint, NOT NULL, FK -> `submissions.id` ON DELETE CASCADE)
- `question_id` (bigint, NOT NULL, FK -> `questions.id` ON DELETE CASCADE)
- `text_value` (text, nullable): Populated when `question_type` is `:text`.
- `number_value` (decimal(15, 2), nullable): Populated when `question_type` is `:number`.
- `selected_option_id` (bigint, nullable, FK -> `question_options.id` ON DELETE SET NULL): Populated when `question_type` is `:multiple_choice`.
- `created_at`, `updated_at` (timestamps)
- **Indexes**: `[submission_id]`, `[question_id]`, `[selected_option_id]`, `[submission_id, question_id]`

---

## 3. Why Normalized Answers Instead of a Single JSON Blob?

Many naive survey tools serialize all submitted form data into an unindexed JSON/JSONB document like `{ "q1": "val1", "q2": 12 }`. While quick to write, that design introduces serious operational and analytical deficits:

1. **Relational Integrity & Foreign Keys**:
   - In our normalized schema, `selected_option_id` has a direct foreign key to `question_options(id)`.
   - If an option is renamed, the relationship remains stable.
   - If an invalid option ID is submitted, PostgreSQL foreign keys and model validations reject the mutation.
2. **True Native Typing**:
   - Number questions are stored in `decimal(15, 2)` columns, preserving exact numeric semantics without floating-point precision issues or JSON string cast errors.
   - Database aggregates (`AVG(number_value)`, `MIN`, `MAX`, `SUM`, percentiles) execute natively in PostgreSQL at microsecond speeds.
3. **Optimized Indexing & Selective Filtering**:
   - Standard B-Tree indexes on `[submission_id, question_id]` and `[selected_option_id]` allow instant lookups.
4. **Data Validation at the Boundary**:
   - Each answer record is strictly validated against its question type: text questions cannot store numbers or option IDs; multiple-choice questions must reference an option that belongs exclusively to that question.

---

## 4. How the Schema Powers Future Analytics

The schema was constructed specifically to enable zero-overhead database aggregations:

- **Responses by Day / Period**:
  ```sql
  SELECT DATE(s.submitted_at) AS day, COUNT(s.id) AS responses
  FROM submissions s
  JOIN surveys surv ON surv.id = s.survey_id
  WHERE surv.customer_id = $CUSTOMER_ID
    AND s.submitted_at >= NOW() - INTERVAL '90 days'
  GROUP BY DATE(s.submitted_at)
  ORDER BY day DESC;
  ```
- **Multiple-Choice Option Distribution**:
  ```sql
  SELECT qo.label, COUNT(a.id) AS votes,
         ROUND(COUNT(a.id) * 100.0 / SUM(COUNT(a.id)) OVER(), 1) AS percentage
  FROM question_options qo
  JOIN questions q ON q.id = qo.question_id
  JOIN surveys s ON s.id = q.survey_id
  LEFT JOIN answers a ON a.selected_option_id = qo.id
  WHERE s.customer_id = $CUSTOMER_ID AND q.id = $QUESTION_ID
  GROUP BY qo.id, qo.label
  ORDER BY qo.position ASC;
  ```
- **Numeric Benchmarking (Averages, Medians, Outliers)**:
  ```sql
  SELECT q.question_text,
         ROUND(AVG(a.number_value), 2) AS average_score,
         MIN(a.number_value) AS min_score,
         MAX(a.number_value) AS max_score
  FROM answers a
  JOIN questions q ON q.id = a.question_id
  JOIN surveys s ON s.id = q.survey_id
  WHERE s.customer_id = $CUSTOMER_ID AND q.question_type = 1 -- number
  GROUP BY q.id, q.question_text;
  ```
- **Survey Completion Rates & Drop-Off Analysis**:
  Because `questions` and `answers` are individually recorded, queries can identify which optional or required questions had the highest drop-off rate without parsing text blobs.
