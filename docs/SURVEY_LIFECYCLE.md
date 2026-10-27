# Survey Lifecycle & Question Engine

This document details the complete lifecycle of a survey in the application—from draft authoring and question modeling to client-side dynamic form interactions and cryptographic token generation upon publishing.

---

## 1. Survey State Machine

Every survey maintains a discrete state represented by an ActiveRecord enum:

```ruby
# app/models/survey.rb
enum :status, { draft: 0, published: 1 }, default: :draft
```

```text
               +----------------------------------+
               |              Draft               |
               | (Private, editable, unanswereable|
               +----------------------------------+
                                │
                                │ User triggers POST /surveys/:id/publish
                                │ Calls @survey.publish!
                                ▼
                       [ publishable? Check ]
                     - Has at least 1 question?
                     - Do MC questions have options?
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
              [ Passed ]                   [ Failed ]
                 │                             │
                 ▼                             ▼
   +---------------------------+    +-----------------------+
   |         Published         |    | Remain in Draft State |
   | (status: 1, public active)|    | Alert error to user   |
   +---------------------------+    +-----------------------+
```

### Draft State (`status: :draft`, `0`)
- Newly created surveys default to `draft`.
- Can be viewed, edited, updated, or deleted by authorized tenant operators.
- **Inaccessible to the public**: Requests to `/s/:public_token` for a draft survey immediately return `404 Not Found`.

### Published State (`status: :published`, `1`)
- Enabled via `POST /surveys/:id/publish`.
- Automatically sets `published_at = Time.current`.
- Actively accepts anonymous public submissions via `/s/:public_token`.

---

## 2. Dynamic Question Modeling & Types

The application supports three distinct question types defined by an enum:

```ruby
# app/models/question.rb
enum :question_type, { text: 0, number: 1, multiple_choice: 2 }, default: :text
```

| Type | Representation in DB | Question Configuration | Validations Enforced | Answer Value Stored |
| :--- | :--- | :--- | :--- | :--- |
| **Text** (`0`) | `questions.question_type = 0` | Question text, required flag. Cannot have options. | `validate_options_for_question_type` ensures options array is empty. | `answers.text_value` (trimmed string) |
| **Number** (`1`) | `questions.question_type = 1` | Question text, required flag. Cannot have options. | Validates options array is empty. | `answers.number_value` (`decimal(15, 2)`) |
| **Multiple Choice** (`2`) | `questions.question_type = 2` | Question text, required flag, 1..N `question_options`. | Requires at least 1 option before survey can be published. | `answers.selected_option_id` (foreign key -> `question_options.id`) |

---

## 3. Nested Attributes & Client-Side Builder (`survey_builder_controller.js`)

Surveys and their questions are created and updated in a single HTTP request using Rails nested attributes:

```ruby
# app/models/survey.rb
accepts_nested_attributes_for :questions, allow_destroy: true, reject_if: :all_blank

# app/models/question.rb
accepts_nested_attributes_for :question_options, allow_destroy: true, reject_if: :all_blank
```

### The Stimulus Builder Engine
The survey form (`app/views/surveys/_form.html.erb`) connects to the Stimulus controller `app/javascript/controllers/survey_builder_controller.js`:

1. **Adding Questions**: The operator clicks "Add Question". The Stimulus controller clones a hidden HTML `<template>` containing a blank question sub-form, generates a unique timestamp index (e.g. `1730000000000`), and appends it to the DOM.
2. **Dynamic Question Type Switching**:
   - When the operator switches a question dropdown to `multiple_choice`, the Stimulus controller toggles the visibility of the options container.
   - For `text` or `number`, the options container is hidden and cleared.
3. **Adding / Removing Options**:
   - Multiple choice options can be added dynamically using an option `<template>`.
   - Removing an option sets the hidden `_destroy` input to `"1"` and hides the element, instructing ActiveRecord to delete the row upon save.
4. **Strong Parameters Permitted Hash**:
   ```ruby
   params.require(:survey).permit(
     :title,
     :description,
     :limit_one_response_per_device,
     questions_attributes: [
       :id,
       :question_text,
       :question_type,
       :position,
       :required,
       :_destroy,
       { question_options_attributes: %i[id label position _destroy] }
     ]
   )
   ```

---

## 4. Public Token Generation & Unguessability

Upon creation, every survey receives an unguessable public token generated via a model callback:

```ruby
# app/models/survey.rb
before_validation :ensure_public_token, on: :create

private

def ensure_public_token
  self.public_token ||= SecureRandom.urlsafe_base64(12)
end
```

### Why Sequential Database IDs Are Not Exposed
1. **Prevent Enumeration & Scraping**: If surveys were accessed via sequential IDs like `/s/1`, `/s/2`, an external actor could easily crawl all published surveys across all tenants.
2. **Prevent Business Intelligence Leakage**: Sequential IDs reveal how many surveys have been created on the platform.
3. **Cryptographic Entropy**: `SecureRandom.urlsafe_base64(12)` generates 16 bytes of entropy (yielding 72 bits of cryptographic strength), making brute-force URL guessing mathematically infeasible.

---

## 5. Publishing Validation Rules (`Survey#publishable?`)

A draft survey cannot be published if it is malformed:

```ruby
def publishable?
  errors.clear
  errors.add(:base, "Survey must have at least one question to be published.") if questions.reload.empty?

  questions.each do |q|
    if q.multiple_choice? && q.question_options.reload.empty?
      errors.add(:base, "Multiple choice question '#{q.question_text.truncate(30)}' must have at least one option.")
    end
  end

  errors.empty?
end
```

If an operator attempts to publish an empty survey or a multiple-choice question with zero options:
- `publish!` returns `false`.
- The controller halts and displays the specific validation errors in a flash alert.
- The survey remains safely in `draft` status.

---

## 6. Related Documentation
- [System Architecture](ARCHITECTURE.md)
- [Application Flow](APPLICATION_FLOW.md)
- [Public Submission Flow](PUBLIC_SUBMISSION_FLOW.md)
- [Class & Code Guide](CLASS_AND_CODE_GUIDE.md)
