# Database Seeders & Synthetic Historical Data

This document explains the database seeding pipeline, deterministic data generation, multi-tenant partitioning, historical date distribution, and synchronization tasks.

---

## 1. Seed Pipeline Architecture

The application provides a deterministic, repeatable, and idempotent database seeder implemented in [`db/seeds.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/db/seeds.rb).

```text
bin/rails db:seed
       │
       ▼
[ Delete Existing Data in Dependency Order ]
SurveyDailyMetric -> Answer -> Submission -> QuestionOption -> Question -> Survey -> User -> Customer
       │
       ▼
[ Dedicated PRNG Initialization ]
rng = Random.new(42)  <-- Guarantees 100% reproducible results across environments
       │
       ▼
[ Provision Tenants & Administrators ]
Tenant A (Acme Corporation) + Tenant B (Beta Technologies)
       │
       ▼
[ Author Surveys, Questions & Options ]
Acme: 3 surveys (2 published, 1 draft), 5 questions, 7 options
Beta: 1 survey (published), 2 questions, 3 options
       │
       ▼
[ Generate Historical Submissions & Typed Answers ]
157 submissions spanning 89 days (~3 months) across 56 distinct calendar dates
       │
       ▼
[ Pre-Aggregated Metrics Synchronization ]
Rake::Task["analytics:backfill"].invoke (Creates 77 synchronized daily metric rows)
```

---

## 2. Deterministic Generation via Isolated PRNG (`Random.new(42)`)

In Ruby, global calls to `Kernel.rand` or `Array#sample` without an explicit random generator rely on global state that can be perturbed by test runners (e.g. Minitest seeds), web servers, or external gems.

To guarantee that `bin/rails db:seed` generates the **exact same records, dates, and response counts** on every machine and test run, `db/seeds.rb` instantiates an isolated PRNG:

```ruby
# db/seeds.rb
rng = Random.new(42)

# Used consistently across all sampling and random integer calls:
submission_dates = (0..89).to_a.sample(50, random: rng).sort.reverse
submitted_at = date + (i * 2).hours + rng.rand(1..50).minutes
selected = acme_options[rng.rand(0..3)]
text_value: feedback_samples.sample(random: rng)
number_value: BigDecimal(rng.rand(1..25).to_s)
```

---

## 3. Seeded Entities & Exact Record Counts

| Entity / Table | Model Class | Count | Generated Records |
| :--- | :--- | :---: | :--- |
| **`customers`** | `Customer` | **2** | `Acme Corporation` (primary tenant) & `Beta Technologies` (isolation tenant) |
| **`users`** | `User` | **2** | `admin@acme.test` & `beta_admin@beta.test` (password: `ChangeMe123!`) |
| **`surveys`** | `Survey` | **4** | Acme: 2 published, 1 draft; Beta: 1 published |
| **`questions`** | `Question` | **7** | 3 Multiple Choice, 2 Numeric rating/quantity, 2 Freeform text feedback |
| **`question_options`** | `QuestionOption` | **10** | Choices for multiple choice questions |
| **`submissions`** | `Submission` | **157** | Acme CSAT (130) + Acme Product Eval (10) + Beta Onboarding (17) |
| **`answers`** | `Answer` | **403** | 157 MC answers + 157 numeric answers + 89 text feedback answers |
| **`survey_daily_metrics`**| `SurveyDailyMetric` | **77** | Pre-aggregated daily metric rows (sum of `response_count` = 157) |

---

## 4. Historical Date Distribution & Analytics Readiness

The seeded submissions simulate realistic customer engagement spanning **89 days** (~3 months):
- **Start Date**: `2026-07-30`
- **End Date**: `2026-10-27`
- **Active Days**: 56 distinct calendar dates with responses.
- **Daily Volume**: 1 to 6 responses per active day.
- **Multi-Tenant Partitioning**:
  - **Acme Corporation**: 140 submissions across 50 active days.
  - **Beta Technologies**: 17 submissions across 17 active days.
  - **Zero Leakage**: All submissions belong strictly to the survey of that customer.

---

## 5. Dedicated Provisioning Rake Tasks

In addition to `bin/rails db:seed`, the application provides specialized Rake tasks for rapid development provisioning:

### Dual-Tenant Provisioning (`customers:setup`)
```bash
bin/rails customers:setup
```
Idempotently provisions `Acme Corporation` and `Beta Technologies` with login credentials ready for immediate testing.

### Custom Tenant Provisioning (`customers:create_initial`)
```bash
INITIAL_CUSTOMER_NAME="Stark Industries" \
INITIAL_USER_EMAIL="tony@stark.test" \
INITIAL_USER_PASSWORD="SecretPassword123!" \
bin/rails customers:create_initial
```

### Metrics Backfill (`analytics:backfill`)
```bash
bin/rails analytics:backfill
```
Aggregates historical `submissions` into `survey_daily_metrics` using atomic PostgreSQL UPSERT.

---

## 6. Automated Verification Test Suite

A dedicated automated test file verifies the seeding engine at [`test/models/seed_data_test.rb`](file:///c:/Users/Lenovo/Documents/Multi-Tenant/test/models/seed_data_test.rb):

```bash
bin/rails test test/models/seed_data_test.rb
```

### Test Cases Covered:
1. `test_seed_file_executes_cleanly_and_populates_all_8_tables_with_deterministic_counts`
2. `test_seed_file_is_idempotent_and_can_be_executed_multiple_times_without_errors`
3. `test_seed_data_strictly_enforces_referential_integrity_without_orphan_records`
4. `test_seed_data_enforces_strict_multi_tenant_customer_isolation`
5. `test_seed_submissions_span_approximately_3_months_and_provide_rich_daily_distribution_for_analytics`
6. `test_survey_daily_metrics_table_accurately_mirrors_submission_dates_and_response_counts`

---

## 7. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Analytics Flow](ANALYTICS_FLOW.md)
- [Database Design](DATABASE_DESIGN.md)
- [Project Cheat Sheet](PROJECT_CHEATSHEET.md)
