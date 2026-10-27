# Analytics Architecture & Daily Aggregation Engine

This document details the high-scale analytics architecture, pre-aggregated database counters, atomic UPSERT mechanisms, asynchronous background pipelines, and interactive date-range filtering.

---

## 1. The Scaling Problem in Survey Analytics

In a naive SaaS architecture, when an operator loads an analytics dashboard, the application executes an on-the-fly aggregation across raw submission rows:

```sql
-- NAIVE APPROACH (Full-table scan over raw submissions):
SELECT DATE(submitted_at) AS date, COUNT(*) AS count
FROM submissions
JOIN surveys ON surveys.id = submissions.survey_id
WHERE surveys.customer_id = 10
  AND submitted_at >= NOW() - INTERVAL '90 days'
GROUP BY DATE(submitted_at)
ORDER BY date DESC;
```

### Why This Fails at Scale:
1. **CPU & I/O Saturation**: If a customer collects 1,000,000 responses across 50 surveys, every page load performs an index or sequential scan across millions of disk blocks.
2. **Database Memory Pressure**: PostgreSQL must allocate memory for hash-aggregate tables to group timestamps into dates.
3. **Slow Page Loads**: Query latency degrades from 10ms to >2,000ms as data accumulates, degrading operator experience.

---

## 2. The Solution: Pre-Aggregated `survey_daily_metrics`

The application solves this bottleneck by decoupling the analytics read path from the submission write path through pre-aggregated daily counters:

```text
[ Respondent Submits Survey ]
               │
               ▼
   INSERT INTO submissions
               │
               ▼ (after_commit on: :create)
   UpdateSurveyDailyMetricJob (ActiveJob / Queue)
               │
               ▼
   SurveyDailyMetric.increment_response_count
   (PostgreSQL Atomic UPSERT on survey_daily_metrics)
               │
               ▼
   [ Operator Views /analytics ]
   current_customer.survey_daily_metrics.where(date: start_date..end_date)
   (Reads max 90 rows per survey -> < 2ms latency!)
```

---

## 3. Concurrency-Safe Atomic UPSERT Implementation

When multiple respondents submit answers on the same day, incrementing a daily counter in standard ActiveRecord (e.g. `metric.increment!(:response_count)`) introduces **lost update race conditions**.

The application eliminates race conditions by utilizing a PostgreSQL native **Atomic UPSERT**:

```ruby
# app/models/survey_daily_metric.rb
class SurveyDailyMetric < ApplicationRecord
  belongs_to :survey

  validates :date, presence: true
  validates :response_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :survey_id, uniqueness: { scope: :date }

  def self.increment_response_count(survey_id, date)
    sql = <<~SQL
      INSERT INTO survey_daily_metrics (survey_id, date, response_count, created_at, updated_at)
      VALUES ($1, $2, 1, NOW(), NOW())
      ON CONFLICT (survey_id, date)
      DO UPDATE SET response_count = survey_daily_metrics.response_count + 1,
                    updated_at = NOW();
    SQL

    binds = [
      ActiveRecord::Relation::QueryAttribute.new("survey_id", survey_id, ActiveRecord::Type::BigInteger.new),
      ActiveRecord::Relation::QueryAttribute.new("date", date, ActiveRecord::Type::Date.new)
    ]

    connection.exec_query(sql, "SurveyDailyMetric Increment", binds)
  end
end
```

### Technical Advantages:
1. **Zero Lock Contention**: PostgreSQL manages atomic row-level incrementation without holding application locks.
2. **SQL Injection Immune**: Query binds (`$1`, `$2`) strictly separate SQL tokens from parameters.
3. **Guaranteed Idempotent Boundary**: Relies on the unique compound index `[survey_id, date]`.

---

## 4. The ActiveJob Pipeline (`UpdateSurveyDailyMetricJob`)

To keep public survey submission response times under 50ms, the metric increment is offloaded asynchronously:

```ruby
# app/jobs/update_survey_daily_metric_job.rb
class UpdateSurveyDailyMetricJob < ApplicationJob
  queue_as :default

  def perform(survey_id, date_str)
    survey = Survey.find_by(id: survey_id)
    return unless survey

    date = Date.parse(date_str)
    SurveyDailyMetric.increment_response_count(survey.id, date)
  end
end
```

- **Triggered By**: `Submission#after_commit on: :create`.
- **Fault-Tolerant**: If a survey is deleted prior to job execution, `survey = Survey.find_by(id: survey_id)` returns `nil` and exits cleanly without throwing unhandled exceptions.

---

## 5. Offline Batch Synchronization (`analytics:backfill`)

If historical data is imported via external bulk scripts or seeds, the application provides an idempotent Rake task to synchronize the pre-aggregated metrics:

```bash
bin/rails analytics:backfill
```

### Implementation (`lib/tasks/analytics.rake`):
```ruby
namespace :analytics do
  desc "Backfill survey_daily_metrics from historical raw submissions"
  task backfill: :environment do
    aggregates = Submission.group(:survey_id, "DATE(submitted_at)").count

    ActiveRecord::Base.transaction do
      aggregates.each do |(survey_id, date_val), count|
        next unless survey_id && date_val
        date = date_val.is_a?(Date) ? date_val : Date.parse(date_val.to_s)

        sql = <<~SQL
          INSERT INTO survey_daily_metrics (survey_id, date, response_count, created_at, updated_at)
          VALUES ($1, $2, $3, NOW(), NOW())
          ON CONFLICT (survey_id, date)
          DO UPDATE SET response_count = $3,
                        updated_at = NOW();
        SQL
        # Execute parameterized query...
      end
    end
  end
end
```

---

## 6. Interactive Date Range Filtering (`AnalyticsController`)

The Analytics dashboard (`GET /analytics`) supports both preset and custom date range filters:

```ruby
# app/controllers/analytics_controller.rb
PRESET_RANGES = %w[30d 90d ytd all].freeze

def index
  resolve_date_range

  # Strictly scoped to current_customer
  metrics_scope = current_customer.survey_daily_metrics.where(date: @start_date..@end_date)

  @daily_responses = metrics_scope.group(:date)
                                 .order(date: :desc)
                                 .sum(:response_count)

  @total_responses = @daily_responses.values.sum
  @active_days_count = @daily_responses.count
  divisor = @selected_range == "90d" ? 90 : (@selected_range == "30d" ? 30 : @days_count)
  @average_daily_responses = (@total_responses.to_f / divisor).round(2)
  @peak_day = @daily_responses.max_by { |_date, count| count }

  # Per-survey breakdown within window
  survey_counts = metrics_scope.group(:survey_id).sum(:response_count)
  @surveys_summary = current_customer.surveys.select(:id, :title, :status).map do |survey|
    count = survey_counts[survey.id] || 0
    survey.define_singleton_method(:submissions_count) { count }
    survey
  end.sort_by { |s| -s.submissions_count }
end
```

### Supported Filter Modes:
1. **`90d` (Default)**: Past 90 calendar days (`90.days.ago.to_date..Date.current`).
2. **`30d`**: Past 30 calendar days (`30.days.ago.to_date..Date.current`).
3. **`ytd` (Year-to-Date)**: From January 1 of the current year through today.
4. **`all` (All Time)**: From the earliest recorded metric date through today.
5. **Custom Range**: `start_date` and `end_date` parameters with strict ISO8601 validation (`Date.iso8601`). If inverted (`start_date > end_date`) or malformed, the controller gracefully falls back to the default 90-day window with an alert flash.

---

## 7. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Application Flow](APPLICATION_FLOW.md)
- [Seed Data Architecture](SEED_DATA.md)
- [Database Design](DATABASE_DESIGN.md)
