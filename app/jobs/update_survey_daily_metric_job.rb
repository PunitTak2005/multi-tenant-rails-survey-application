# frozen_string_literal: true

class UpdateSurveyDailyMetricJob < ApplicationJob
  queue_as :default

  def perform(survey_id, date_str)
    survey = Survey.find_by(id: survey_id)
    return unless survey

    date = Date.parse(date_str)
    SurveyDailyMetric.increment_response_count(survey.id, date)
  end
end
