puts "==> Starting database seed process..."

# Clear existing seed data cleanly in order of dependencies
SurveyDailyMetric.delete_all
Answer.delete_all
Submission.delete_all
QuestionOption.delete_all
Question.delete_all
Survey.delete_all
User.delete_all
Customer.delete_all

# 1. Customer A: Acme Corporation
puts "--> Creating Customer A: Acme Corporation"
acme = Customer.create!(name: "Acme Corporation")

acme_admin = acme.users.create!(
  name: "Acme Admin",
  email: "admin@acme.test",
  password: "ChangeMe123!"
)

# Acme Survey 1 (Published)
acme_survey_1 = acme.surveys.create!(
  title: "Customer Satisfaction Survey",
  description: "Help us improve our B2B SaaS platform by sharing your honest feedback.",
  status: :published,
  published_at: 90.days.ago,
  public_token: "acme-csat-2026"
)

q1 = acme_survey_1.questions.create!(
  question_text: "How satisfied are you with our service?",
  question_type: :multiple_choice,
  position: 1,
  required: true
)
opt_very_sat = q1.question_options.create!(label: "Very satisfied", position: 1)
opt_sat = q1.question_options.create!(label: "Satisfied", position: 2)
opt_neutral = q1.question_options.create!(label: "Neutral", position: 3)
opt_unsat = q1.question_options.create!(label: "Unsatisfied", position: 4)

q2 = acme_survey_1.questions.create!(
  question_text: "Tell us what we can improve.",
  question_type: :text,
  position: 2,
  required: false
)

q3 = acme_survey_1.questions.create!(
  question_text: "How many times have you used our service?",
  question_type: :number,
  position: 3,
  required: true
)

# Acme Survey 2 (Published)
acme_survey_2 = acme.surveys.create!(
  title: "Product Feature Evaluation",
  description: "Evaluating our key workflow modules and performance metrics.",
  status: :published,
  published_at: 45.days.ago,
  public_token: "acme-product-eval"
)

q2_1 = acme_survey_2.questions.create!(
  question_text: "Which module is most critical to your workflow?",
  question_type: :multiple_choice,
  position: 1,
  required: true
)
opt_m1 = q2_1.question_options.create!(label: "Analytics & Reporting", position: 1)
opt_m2 = q2_1.question_options.create!(label: "Automations", position: 2)
opt_m3 = q2_1.question_options.create!(label: "Team Collaboration", position: 3)

q2_2 = acme_survey_2.questions.create!(
  question_text: "Rate overall system speed (1-10)",
  question_type: :number,
  position: 2,
  required: true
)

# Acme Survey 3 (Draft)
acme.surveys.create!(
  title: "2026 Customer Feedback & Roadmap",
  description: "Internal draft for upcoming Q4 customer research initiative.",
  status: :draft,
  public_token: "acme-draft-roadmap"
)

# 2. Customer B: Beta Technologies (for Tenant Isolation testing)
puts "--> Creating Customer B: Beta Technologies"
beta = Customer.create!(name: "Beta Technologies")

beta_admin = beta.users.create!(
  name: "Beta Admin",
  email: "beta_admin@beta.test",
  password: "ChangeMe123!"
)

beta_survey = beta.surveys.create!(
  title: "Beta Platform Onboarding Survey",
  description: "Feedback on initial account setup and ease of configuration.",
  status: :published,
  published_at: 60.days.ago,
  public_token: "beta-onboarding-survey"
)

beta_q1 = beta_survey.questions.create!(
  question_text: "How easy was the initial onboarding?",
  question_type: :multiple_choice,
  position: 1,
  required: true
)
beta_opt1 = beta_q1.question_options.create!(label: "Very easy", position: 1)
beta_opt2 = beta_q1.question_options.create!(label: "Average", position: 2)
beta_opt3 = beta_q1.question_options.create!(label: "Challenging", position: 3)

beta_q2 = beta_survey.questions.create!(
  question_text: "How many team members are actively using your account?",
  question_type: :number,
  position: 2,
  required: true
)

# 3. Seed Realistic Historical Submissions spread over 3 months
puts "--> Generating historical submissions across past 90 days..."

acme_options = [ opt_very_sat, opt_sat, opt_neutral, opt_unsat ]
feedback_samples = [
  "Love the intuitive multi-tenant layout and swift loading speed.",
  "Reports are clear, would appreciate scheduled email exports.",
  "Clean interface, works reliably on mobile browsers.",
  "Great customer support response times when setting up.",
  "Solid product, looking forward to future feature updates.",
  "Smooth transition from our previous survey tool."
]

# Generate submissions for Acme Corporation
submission_dates = (0..89).to_a.sample(50).sort.reverse # 50 distinct days with activity
total_acme_submissions = 0

submission_dates.each do |days_ago|
  date = days_ago.days.ago
  # 1 to 4 responses on active days
  responses_today = (days_ago % 4) + 1

  responses_today.times do |i|
    submitted_at = date + (i * 2).hours + rand(1..50).minutes
    sub = acme_survey_1.submissions.create!(submitted_at: submitted_at)

    # Answer 1 (Multiple Choice)
    selected = acme_options[rand(0..3)]
    sub.answers.create!(
      question: q1,
      selected_option: selected
    )

    # Answer 2 (Text, occasional blank)
    if rand > 0.3
      sub.answers.create!(
        question: q2,
        text_value: feedback_samples.sample
      )
    end

    # Answer 3 (Number)
    sub.answers.create!(
      question: q3,
      number_value: BigDecimal(rand(1..25).to_s)
    )

    total_acme_submissions += 1
  end

  # Acme survey 2 responses for dates within last 45 days
  if days_ago <= 45 && days_ago % 3 == 0
    sub2 = acme_survey_2.submissions.create!(submitted_at: date + 4.hours)
    sub2.answers.create!(
      question: q2_1,
      selected_option: [ opt_m1, opt_m2, opt_m3 ].sample
    )
    sub2.answers.create!(
      question: q2_2,
      number_value: BigDecimal(rand(7..10).to_s)
    )
    total_acme_submissions += 1
  end
end

# Generate submissions for Beta Technologies
beta_options = [ beta_opt1, beta_opt2, beta_opt3 ]
total_beta_submissions = 0

(0..50).step(3).each do |days_ago|
  date = days_ago.days.ago
  sub = beta_survey.submissions.create!(submitted_at: date + 3.hours)
  sub.answers.create!(
    question: beta_q1,
    selected_option: beta_options.sample
  )
  sub.answers.create!(
    question: beta_q2,
    number_value: BigDecimal(rand(2..50).to_s)
  )
  total_beta_submissions += 1
end

# Ensure pre-aggregated daily metrics are 100% in sync with historical submissions
puts "--> Synchronizing survey daily metrics..."
Rails.application.load_tasks unless Rake::Task.task_defined?("analytics:backfill")
Rake::Task["analytics:backfill"].reenable
Rake::Task["analytics:backfill"].invoke

puts "✓ Successfully seeded:"
puts "  - Customer Acme Corporation: #{acme.surveys.count} surveys, #{total_acme_submissions} submissions"
puts "  - Customer Beta Technologies: #{beta.surveys.count} surveys, #{total_beta_submissions} submissions"
puts "  - User Acme: #{acme_admin.email} (Password: ChangeMe123!)"
puts "  - User Beta: #{beta_admin.email} (Password: ChangeMe123!)"
puts "==> Seed process finished successfully!"
