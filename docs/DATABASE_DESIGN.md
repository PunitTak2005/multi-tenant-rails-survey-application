# Database & Multi-Tenancy Architecture Design

This document details the relational database schema, normalization rationale, indexing strategy, tenant isolation boundaries, and high-scale analytics architecture for the **Multi-Tenant Survey SaaS Application**.

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
        │     └── QuestionOptions (Choices for multiple-choice questions)
        │
        ├── Submissions (Public response sessions)
        │     │
        │     └── Answers (Normalized responses linked to Question & Submission)
        │
        └── SurveyDailyMetrics (Pre-aggregated daily response counts for high-scale analytics)
```

---

## 2. Complete Relational Schema Specifications

### `customers`
Represents organizational tenants. All private SaaS entities belong directly or indirectly to a customer record.
- **`id`** (`bigserial`, Primary Key)
- **`name`** (`varchar`, NOT NULL): Company or tenant name.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)

### `users`
Authenticated operators belonging strictly to a customer.
- **`id`** (`bigserial`, Primary Key)
- **`customer_id`** (`bigint`, NOT NULL, FK -> `customers.id` ON DELETE CASCADE)
- **`email`** (`varchar`, NOT NULL, Unique): Normalized lowercase email address.
- **`password_digest`** (`varchar`, NOT NULL): BCrypt salted password hash.
- **`name`** (`varchar`, NOT NULL): Operator display name.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[email]` (UNIQUE): Enforces global email uniqueness and accelerates login lookups.
  - `[customer_id]`: Optimizes tenant-scoped user lookups.

### `surveys`
Surveys created and owned by customer tenants.
- **`id`** (`bigserial`, Primary Key)
- **`customer_id`** (`bigint`, NOT NULL, FK -> `customers.id` ON DELETE CASCADE)
- **`title`** (`varchar`, NOT NULL): Human-readable survey title.
- **`description`** (`text`): Instructions displayed to respondents.
- **`status`** (`integer`, NOT NULL, default: `0`): Enum (`0: draft`, `1: published`).
- **`public_token`** (`varchar`, NOT NULL, Unique): Cryptographic random token used in public URL `/s/:public_token`. Internal serial IDs are never exposed.
- **`published_at`** (`timestamp`): Timestamp when survey was published.
- **`limit_one_response_per_device`** (`boolean`, NOT NULL, default: `false`): Restricts responses to one submission per browser.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[public_token]` (UNIQUE): Instant $O(1)$ lookup for public respondent requests without exposing database IDs.
  - `[customer_id]`: Accelerates tenant-scoped queries (`current_customer.surveys`).
  - `[customer_id, status]`: Optimizes dashboard metric counters (`current_customer.surveys.published.count`).
  - `[customer_id, created_at]`: Accelerates recent survey listings on the dashboard.

### `questions`
Ordered questions configured within a survey.
- **`id`** (`bigserial`, Primary Key)
- **`survey_id`** (`bigint`, NOT NULL, FK -> `surveys.id` ON DELETE CASCADE)
- **`question_text`** (`text`, NOT NULL): Question prompt displayed to respondents.
- **`question_type`** (`integer`, NOT NULL, default: `0`): Enum (`0: text`, `1: number`, `2: multiple_choice`).
- **`position`** (`integer`, NOT NULL, default: `1`): 1-based order index.
- **`required`** (`boolean`, NOT NULL, default: `false`): Enforces answer completion upon submission.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[survey_id]`: Supports survey cascade deletion and question collection loading.
  - `[survey_id, position]`: Guarantees fast, indexed question ordering when displaying survey forms.

### `question_options`
Selectable choices for multiple-choice questions.
- **`id`** (`bigserial`, Primary Key)
- **`question_id`** (`bigint`, NOT NULL, FK -> `questions.id` ON DELETE CASCADE)
- **`label`** (`varchar`, NOT NULL): Option text label (e.g. "Very satisfied").
- **`position`** (`integer`, NOT NULL, default: `1`): 1-based display order.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[question_id]`: Accelerates options retrieval for a question.
  - `[question_id, position]`: Supports deterministic ordering of multiple choice options.

### `submissions`
Session record representing a single completed response to a published survey.
- **`id`** (`bigserial`, Primary Key)
- **`survey_id`** (`bigint`, NOT NULL, FK -> `surveys.id` ON DELETE CASCADE)
- **`submitted_at`** (`timestamp`, NOT NULL): Exact completion time.
- **`respondent_token_digest`** (`varchar`, nullable): SHA256 digest of signed browser cookie token for single-response device enforcement.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[survey_id]`: Foreign key index for survey submissions lookups.
  - `[survey_id, submitted_at]`: Optimizes paginated submissions view (`order(submitted_at: :desc)`).
  - `[submitted_at]`: Optimizes historical date-range analytics scans.
  - `[survey_id, respondent_token_digest]` (UNIQUE, WHERE `respondent_token_digest IS NOT NULL`): Partial unique index enforcing strict single-submission constraint per browser while preserving NULL anonymity for standard surveys.

### `answers`
Discrete, typed response values linked to both a `submission` and a specific `question`.
- **`id`** (`bigserial`, Primary Key)
- **`submission_id`** (`bigint`, NOT NULL, FK -> `submissions.id` ON DELETE CASCADE)
- **`question_id`** (`bigint`, NOT NULL, FK -> `questions.id` ON DELETE CASCADE)
- **`text_value`** (`text`, nullable): Populated when `question_type` is `:text`.
- **`number_value`** (`decimal(15, 2)`, nullable): Populated when `question_type` is `:number`.
- **`selected_option_id`** (`bigint`, nullable, FK -> `question_options.id` ON DELETE SET NULL): Populated when `question_type` is `:multiple_choice`.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[submission_id]`: Accelerates answer loading for a specific submission.
  - `[question_id]`: Enables analytics queries across all answers to a specific question.
  - `[selected_option_id]`: Foreign key index accelerating option distribution queries.
  - `[submission_id, question_id]`: Compound index optimizing answer lookup per question during detail rendering.

### `survey_daily_metrics`
Pre-aggregated daily response counters ensuring instantaneous $O(\text{days})$ analytics dashboard queries under high-volume production datasets.
- **`id`** (`bigserial`, Primary Key)
- **`survey_id`** (`bigint`, NOT NULL, FK -> `surveys.id` ON DELETE CASCADE)
- **`date`** (`date`, NOT NULL): Calendar date of the response bucket.
- **`response_count`** (`integer`, NOT NULL, default: `0`): Total completed submissions for the survey on that date.
- **`created_at`, `updated_at`** (`timestamp`, NOT NULL)
- **Indexes**:
  - `[survey_id, date]` (UNIQUE): Primary concurrency boundary preventing duplicate metric rows and enabling atomic PostgreSQL UPSERT (`ON CONFLICT (survey_id, date) DO UPDATE`).
  - `[date]`: Accelerates date range filtering (`where(date: start_date..end_date)`).
  - `[survey_id]`: Supports survey cascade deletion.

---

## 3. Database Normalization Defense (1NF, 2NF, 3NF vs JSONB)

### 1NF (First Normal Form): Atomic Values
- Each column contains indivisible values (no comma-separated strings or embedded arrays).
- Every record has a unique primary key.

### 2NF (Second Normal Form): Full Functional Dependency
- All non-key attributes depend entirely on the primary key, not a subset.
- Question options are extracted into `question_options` rather than storing an array inside `questions`.

### 3NF (Third Normal Form): No Transitive Dependencies
- Non-key columns depend only on the primary key, with no transitive relationships.
- Submissions store only `survey_id` and timestamps. Answers store question values linked to `submission_id` and `question_id`.

### Why Not Store Answers in a Single JSON Blob?
Many naive survey platforms store all respondent answers in a single JSONB column on `submissions` (e.g. `{ "q1": "val", "q2": 42 }`). Our normalized relational design was deliberately selected for the following technical reasons:

| Relational Normalized Design | Single JSON/JSONB Column Design |
| :--- | :--- |
| **Referential Integrity**: Foreign keys (`FK selected_option_id -> question_options.id`) prevent phantom option references. | **No Referential Integrity**: Storing option IDs in JSON allows corrupted/deleted IDs without database notification. |
| **Native Typing**: Numbers stored as `decimal(15, 2)` support microsecond SQL math (`AVG`, `SUM`, `MIN`, `MAX`, percentiles). | **Type Uncertainty**: Values in JSON are strings or untyped floats prone to parsing and IEEE 754 precision errors. |
| **Direct Indexing**: PostgreSQL B-Trees on `selected_option_id` make aggregating choice distributions instantaneous. | **Expensive JSON Traversal**: Requires GIN indexing or full JSON document decompression on every query. |
| **Boundary Validation**: Database constraints reject invalid states (e.g. nullifying selected options on deletion). | **Application-Only Validation**: Corrupt records can be injected via direct database scripts or buggy worker processes. |

---

## 4. Foreign Key Cascade & Referential Integrity Matrix

| Child Table | Foreign Key Column | Parent Table | On Delete Action | Technical Justification |
| :--- | :--- | :--- | :---: | :--- |
| `users` | `customer_id` | `customers` | `CASCADE` | When an organizational customer is deleted, all user accounts must be removed. |
| `surveys` | `customer_id` | `customers` | `CASCADE` | Surveys belong exclusively to the customer organization. |
| `questions` | `survey_id` | `surveys` | `CASCADE` | Questions have no meaning outside their parent survey. |
| `question_options` | `question_id` | `questions` | `CASCADE` | Multiple choice options belong to their parent question. |
| `submissions` | `survey_id` | `surveys` | `CASCADE` | Submissions belong exclusively to their survey. |
| `answers` | `submission_id` | `submissions` | `CASCADE` | Deleting a submission removes all of its associated answers. |
| `answers` | `question_id` | `questions` | `CASCADE` | Answers cannot exist without their corresponding question. |
| `answers` | `selected_option_id`| `question_options`| `NULLIFY` | If an option is removed, historical answers preserve the submission record while clearing the option pointer. |
| `survey_daily_metrics` | `survey_id`| `surveys` | `CASCADE` | Aggregated analytics metrics are purged with the survey. |

---

## 5. Scalable Analytics Architecture Defense

### The Scaling Problem with Raw Submission Aggregation
In high-volume applications collecting millions of submissions, querying raw tables with `GROUP BY DATE(submitted_at)` suffers significant degradation:
- Requires full sequential or index scans over millions of rows.
- High memory pressure for group-by hash tables in PostgreSQL.
- Long response times (>2,000ms), unacceptable for interactive dashboards.

### The Solution: Pre-Aggregated `survey_daily_metrics` Table
1. **Asynchronous Background Processing**: When a submission is persisted, an ActiveJob (`UpdateSurveyDailyMetricJob`) runs asynchronously outside the respondent request lifecycle.
2. **Concurrency-Safe Atomic UPSERT**:
   ```sql
   INSERT INTO survey_daily_metrics (survey_id, date, response_count, created_at, updated_at)
   VALUES ($1, $2, 1, NOW(), NOW())
   ON CONFLICT (survey_id, date)
   DO UPDATE SET response_count = survey_daily_metrics.response_count + 1,
                 updated_at = NOW();
   ```
3. **Instantaneous Dashboard Response**: For a 90-day window, the database scans at most 90 rows per survey. Query latency drops to **< 2ms**, completely decoupled from the total submission volume.
4. **Offline Backfill Capability**: Rake task `bin/rails analytics:backfill` recalculates metrics from raw submissions whenever needed.

---

## 6. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Application Flow](APPLICATION_FLOW.md)
- [Class & Code Guide](CLASS_AND_CODE_GUIDE.md)
- [Security Architecture](SECURITY.md)
