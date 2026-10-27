class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  def index
    @start_date = 90.days.ago.to_date
    @end_date = Date.current

    # Read pre-aggregated daily metrics strictly scoped to current_customer.
    # No full-table scans or expensive group-by aggregations on raw submissions table.
    @daily_responses = current_customer.survey_daily_metrics
                                       .where(date: @start_date..@end_date)
                                       .group(:date)
                                       .order(date: :desc)
                                       .sum(:response_count)

    @total_responses = @daily_responses.values.sum
    @active_days_count = @daily_responses.count
    @average_daily_responses = (@total_responses.to_f / 90).round(2)
    @peak_day = @daily_responses.max_by { |_date, count| count }

    # Per-survey response counts read from pre-aggregated daily metrics
    survey_counts = current_customer.survey_daily_metrics
                                    .group(:survey_id)
                                    .sum(:response_count)

    @surveys_summary = current_customer.surveys.select(:id, :title, :status).map do |survey|
      count = survey_counts[survey.id] || 0
      survey.define_singleton_method(:submissions_count) { count }
      survey
    end.sort_by { |s| -s.submissions_count }
  end
end
