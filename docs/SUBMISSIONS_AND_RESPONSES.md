# Submissions Listing & Response Details

This document explains how customer operators access, browse, and inspect survey submissions, detailing the pagination architecture, N+1 query prevention, answer-to-question matching, and IDOR defenses.

---

## 1. Flow Overview: From Survey to Submission Breakdown

```text
Customer Operator
       │
       ▼
GET /surveys/:survey_id/submissions (Submissions Index)
       │
  ┌────┴───────────────────────────────────────────────────────┐
  │ 1. Tenant & Survey Scoping:                                 │
  │    @survey = current_customer.surveys.find(params[:survey_id])│
  │ 2. Pagy Offset Pagination (default 20, max 100, sanitized) │
  │ 3. Eager Loading:                                          │
  │    @survey.submissions.includes(answers: %i[question selected_option])
  └────┬───────────────────────────────────────────────────────┘
       │
       ▼ (Operator clicks on a specific submission)
GET /surveys/:survey_id/submissions/:id (Submission Detail)
       │
  ┌────┴───────────────────────────────────────────────────────┐
  │ 1. Two-Level Scoping:                                       │
  │    @submission = @survey.submissions.find(params[:id])     │
  │ 2. Answer-to-Question Alignment:                            │
  │    existing_answers = @submission.answers.index_by(&:question_id)
  │    @answers = @survey.questions.map do |q|                 │
  │      existing_answers[q.id] || @submission.answers.build(q)│
  │    end                                                     │
  │ 3. Type-Safe Rendering (Text, Number, Multiple Choice)     │
  └────────────────────────────────────────────────────────────┘
```

---

## 2. Paginated Submissions Listing (`submissions#index`)

When inspecting submissions for a survey with hundreds or thousands of responses, loading all records simultaneously causes severe memory bloat and slow response times. The application implements high-performance offset pagination via **Pagy 9**:

```ruby
# app/controllers/submissions_controller.rb
DEFAULT_PER_PAGE = 20
MAX_PER_PAGE = 100

def index
  page = sanitize_page(params[:page])
  limit = sanitize_limit(params[:limit] || params[:per_page])

  total_count = @survey.submissions.count
  @pagy = Pagy::Offset.new(count: total_count, page: page, limit: limit)

  @submissions = if @pagy.in_range?
    @survey.submissions
           .order(submitted_at: :desc, id: :desc)
           .offset(@pagy.offset)
           .limit(@pagy.limit)
           .includes(answers: %i[question selected_option])
  else
    @survey.submissions.none
  end
end
```

### Key Technical Details:
1. **Input Sanitization**:
   - `sanitize_page`: Rejects negative integers, zero, decimals, and malicious strings, defaulting cleanly to `1`.
   - `sanitize_limit`: Clamps the requested limit between `1` and `MAX_PER_PAGE` (100), defaulting to `20`. Prevents DoS attempts requesting `limit=1000000`.
2. **Deterministic Ordering**: Orders by `submitted_at: :desc, id: :desc`. The tiebreaker `id: :desc` prevents duplicate or missing rows across page boundaries when multiple submissions share an identical timestamp.
3. **Out-of-Range Handling**: If a user requests page `99999` beyond total records, `@pagy.in_range?` returns `false`, rendering an empty state without throwing exceptions.

---

## 3. Eliminating N+1 Queries via Eager Loading

In naive Rails applications, rendering a table of submissions that displays each submission's answers results in an N+1 query disaster:
- 1 query for submissions
- N queries for answers
- N queries for questions
- N queries for selected options

The application solves this via ActiveRecord eager loading:
```ruby
.includes(answers: %i[question selected_option])
```
- **Execution in PostgreSQL**: Executes exactly **4 optimized queries** regardless of whether page size is 20, 50, or 100:
  1. `SELECT COUNT(*) FROM submissions WHERE survey_id = $1` (pagination count)
  2. `SELECT * FROM submissions WHERE survey_id = $1 ORDER BY submitted_at DESC, id DESC LIMIT $2 OFFSET $3`
  3. `SELECT * FROM answers WHERE submission_id IN (...)`
  4. `SELECT * FROM questions WHERE id IN (...)` and `SELECT * FROM question_options WHERE id IN (...)`

---

## 4. Submission Detail & Unanswered Questions (`submissions#show`)

In `SubmissionsController#show`, each submission displays all questions asked on the survey alongside the respondent's answers.

### The Problem with Optional Questions
Surveys often feature optional questions. If a respondent skips Question 2, the `answers` table contains rows for Question 1 and Question 3, but **no record exists for Question 2**. A simple join (`@submission.answers`) would omit Question 2 entirely, confusing the operator.

### The Solution: Question-Anchored Mapping
The controller anchors the view to the survey's question catalog rather than raw answer records:

```ruby
def show
  @submission = @survey.submissions.find(params[:id])
  existing_answers = @submission.answers.includes(:question, :selected_option).index_by(&:question_id)
  @answers = @survey.questions.order(:position).includes(:question_options).map do |question|
    existing_answers[question.id] || @submission.answers.build(question: question)
  end
end
```

1. **Hash Lookup**: `index_by(&:question_id)` converts existing answers into an $O(1)$ memory lookup hash.
2. **Placeholder Generation**: If an answer exists, it is displayed. If not, `@submission.answers.build(question: question)` creates an in-memory, unpersisted placeholder.
3. **UI Rendering**: The view checks `answer.persisted?`:
   - If persisted: Renders `answer.display_value`.
   - If not persisted: Renders a muted `"Not answered"` badge.

---

## 5. Type-Safe Answer Formatting (`Answer#display_value`)

Formatting logic is cleanly encapsulated inside the `Answer` model rather than cluttered in view helpers:

```ruby
# app/models/answer.rb
def display_value
  if question.text?
    text_value
  elsif question.number?
    number_value.to_s
  elsif question.multiple_choice?
    selected_option&.label || "No option selected"
  end
end
```

- **Text Questions**: Renders raw string (`text_value`) auto-escaped by Rails ERB to prevent XSS.
- **Number Questions**: Formats numeric string from `BigDecimal`.
- **Multiple Choice**: Resolves the associated `QuestionOption#label` (e.g. `"Very satisfied"`), gracefully handling nullified options if a choice was subsequently deleted.

---

## 6. Multi-Tenant & Cross-Survey IDOR Defense

The controller enforces strict two-level query scoping:

```ruby
# 1. Tenant Scope: Verifies the survey belongs to current customer
@survey = current_customer.surveys.find(params[:survey_id])

# 2. Survey Scope: Verifies the submission belongs to that specific survey
@submission = @survey.submissions.find(params[:id])
```

- **Cross-Tenant Attack**: User A attempts to view submission 500 owned by Customer B:
  - `@survey = current_customer.surveys.find(...)` raises `ActiveRecord::RecordNotFound`.
- **Cross-Survey Attack**: User A owns Survey 1 and Survey 2. User A attempts to open submission 400 (belonging to Survey 2) under URL `/surveys/1/submissions/400`:
  - `@survey.submissions.find(400)` raises `ActiveRecord::RecordNotFound` because submission 400 does not belong to Survey 1.

---

## 7. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Application Flow](APPLICATION_FLOW.md)
- [Database Design](DATABASE_DESIGN.md)
- [Analytics Flow](ANALYTICS_FLOW.md)
