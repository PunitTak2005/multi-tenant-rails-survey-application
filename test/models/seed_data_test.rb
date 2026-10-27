# frozen_string_literal: true

require "test_helper"
require "rake"
require "stringio"

class SeedDataTest < ActiveSupport::TestCase
  # Since seeds.rb performs delete_all across dependent tables, disable transactional tests
  # for this test case so clean setup and deletion work across raw SQL / transactions.
  self.use_transactional_tests = false

  setup do
    Rails.application.load_tasks unless defined?(Rake::Task) && Rake::Task.task_defined?("analytics:backfill")
    clean_all_tables
  end

  teardown do
    clean_all_tables
  end

  test "seed file executes cleanly and populates all 8 tables with deterministic counts" do
    silence_stream($stdout) do
      load Rails.root.join("db/seeds.rb")
    end

    assert_equal 2, Customer.count, "Expected 2 customers"
    assert_equal 2, User.count, "Expected 2 users"
    assert_equal 4, Survey.count, "Expected 4 surveys"
    assert_equal 7, Question.count, "Expected 7 questions"
    assert_equal 10, QuestionOption.count, "Expected 10 question options"
    assert_equal 157, Submission.count, "Expected 157 submissions"
    assert_equal 403, Answer.count, "Expected 403 answers"
    assert_equal 77, SurveyDailyMetric.count, "Expected 77 daily metric records"

    # Verify per-customer breakdown
    acme = Customer.find_by!(name: "Acme Corporation")
    beta = Customer.find_by!(name: "Beta Technologies")

    assert_equal 1, acme.users.count
    assert_equal "admin@acme.test", acme.users.first.email
    assert_equal 3, acme.surveys.count

    assert_equal 1, beta.users.count
    assert_equal "beta_admin@beta.test", beta.users.first.email
    assert_equal 1, beta.surveys.count
  end

  test "seed file is idempotent and can be executed multiple times without errors" do
    2.times do
      silence_stream($stdout) do
        load Rails.root.join("db/seeds.rb")
      end
    end

    assert_equal 2, Customer.count
    assert_equal 2, User.count
    assert_equal 4, Survey.count
    assert_equal 7, Question.count
    assert_equal 10, QuestionOption.count
    assert_equal 157, Submission.count
    assert_equal 403, Answer.count
    assert_equal 77, SurveyDailyMetric.count
  end

  test "seed data strictly enforces referential integrity without orphan records" do
    silence_stream($stdout) do
      load Rails.root.join("db/seeds.rb")
    end

    # Check for orphan records
    assert_equal 0, Submission.where.missing(:survey).count, "Found orphan submissions"
    assert_equal 0, Answer.where.missing(:submission).count, "Found orphan answers without submission"
    assert_equal 0, Answer.where.missing(:question).count, "Found orphan answers without question"
    assert_equal 0, Question.where.missing(:survey).count, "Found orphan questions"
    assert_equal 0, QuestionOption.where.missing(:question).count, "Found orphan question options"
    assert_equal 0, Survey.where.missing(:customer).count, "Found orphan surveys"
    assert_equal 0, User.where.missing(:customer).count, "Found orphan users"
    assert_equal 0, SurveyDailyMetric.where.missing(:survey).count, "Found orphan daily metrics"

    # Ensure no cross-survey answer pollution
    cross_survey_answers = Answer.joins(:question, :submission)
                                 .where("questions.survey_id != submissions.survey_id")
                                 .count
    assert_equal 0, cross_survey_answers, "Found answers pointing to questions of a different survey"

    # Ensure all multiple choice answers point to valid options for that question
    invalid_options = Answer.joins(:question)
                            .where.not(selected_option_id: nil)
                            .where("selected_option_id NOT IN (SELECT id FROM question_options WHERE question_id = questions.id)")
                            .count
    assert_equal 0, invalid_options, "Found answers with invalid selected_option_id"

    # Ensure text and number answers have valid data
    assert_equal 0, Answer.joins(:question).where(questions: { question_type: "text" }).where(text_value: [ nil, "" ]).count
    assert_equal 0, Answer.joins(:question).where(questions: { question_type: "number" }).where(number_value: nil).count
    assert_equal 0, Answer.joins(:question).where(questions: { question_type: "multiple_choice" }).where(selected_option_id: nil).count
  end

  test "seed data enforces strict multi-tenant customer isolation" do
    silence_stream($stdout) do
      load Rails.root.join("db/seeds.rb")
    end

    acme = Customer.find_by!(name: "Acme Corporation")
    beta = Customer.find_by!(name: "Beta Technologies")

    # Acme surveys and submissions
    acme_survey_ids = acme.surveys.pluck(:id)
    acme_submissions = Submission.where(survey_id: acme_survey_ids)
    assert_equal 140, acme_submissions.count, "Acme should have 140 submissions (130 CSAT + 10 Product Eval)"

    # Beta surveys and submissions
    beta_survey_ids = beta.surveys.pluck(:id)
    beta_submissions = Submission.where(survey_id: beta_survey_ids)
    assert_equal 17, beta_submissions.count, "Beta should have 17 submissions"

    # Cross-tenant check: No Acme survey is owned by Beta
    assert_empty Survey.where(id: acme_survey_ids, customer: beta)
    assert_empty Survey.where(id: beta_survey_ids, customer: acme)

    # Cross-tenant check: No submission leaks across customer boundary
    acme_submission_customer_ids = acme_submissions.joins(:survey).pluck("surveys.customer_id").uniq
    assert_equal [ acme.id ], acme_submission_customer_ids

    beta_submission_customer_ids = beta_submissions.joins(:survey).pluck("surveys.customer_id").uniq
    assert_equal [ beta.id ], beta_submission_customer_ids
  end

  test "seed submissions span approximately 3 months and provide rich daily distribution for analytics" do
    silence_stream($stdout) do
      load Rails.root.join("db/seeds.rb")
    end

    min_date = Submission.minimum(:submitted_at)
    max_date = Submission.maximum(:submitted_at)
    span_in_days = (max_date.to_date - min_date.to_date).to_i

    assert span_in_days >= 85 && span_in_days <= 95, "Expected date span ~90 days (got #{span_in_days} days)"

    distinct_dates_count = Submission.select("DISTINCT DATE(submitted_at)").count
    assert distinct_dates_count >= 50, "Expected at least 50 distinct calendar dates (got #{distinct_dates_count})"

    # Verify submissions are distributed across multiple months
    months_covered = Submission.pluck(:submitted_at).map { |d| "#{d.year}-#{d.month.to_s.rjust(2, '0')}" }.uniq
    assert months_covered.size >= 3, "Expected submissions across at least 3 distinct calendar months"
  end

  test "survey daily metrics table accurately mirrors submission dates and response counts" do
    silence_stream($stdout) do
      load Rails.root.join("db/seeds.rb")
    end

    Survey.find_each do |survey|
      submissions_count = survey.submissions.count
      metrics_sum = survey.daily_metrics.sum(:response_count)
      assert_equal submissions_count, metrics_sum, "Metric response_count sum (#{metrics_sum}) mismatch for survey #{survey.id} (submissions: #{submissions_count})"

      # Verify each individual daily metric matches the submissions count on that date
      survey.daily_metrics.find_each do |metric|
        actual_day_submissions = survey.submissions.where("DATE(submitted_at) = ?", metric.date).count
        assert_equal metric.response_count, actual_day_submissions, "Date #{metric.date} mismatch for survey #{survey.id}"
      end
    end
  end

  private

  def clean_all_tables
    SurveyDailyMetric.delete_all
    Answer.delete_all
    Submission.delete_all
    QuestionOption.delete_all
    Question.delete_all
    Survey.delete_all
    User.delete_all
    Customer.delete_all
  end

  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen(File::NULL)
    stream.sync = true
    yield
  ensure
    stream.reopen(old_stream)
    old_stream.close
  end
end
