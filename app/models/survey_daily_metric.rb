# frozen_string_literal: true

class SurveyDailyMetric < ApplicationRecord
  belongs_to :survey

  validates :date, presence: true
  validates :response_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :survey_id, uniqueness: { scope: :date }

  # Concurrency-safe atomic UPSERT for daily metric increments
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
