class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  def index
    @start_date = 90.days.ago.to_date
    @end_date = Date.current

    # Database-level aggregation strictly scoped to current_customer
    @daily_responses = current_customer.submissions
                                       .where("submissions.submitted_at >= ?", @start_date.beginning_of_day)
                                       .where("submissions.submitted_at <= ?", @end_date.end_of_day)
                                       .group("DATE(submissions.submitted_at)")
                                       .order("DATE(submissions.submitted_at) DESC")
                                       .count

    @total_responses = @daily_responses.values.sum
    @active_days_count = @daily_responses.count
    @average_daily_responses = (@total_responses.to_f / 90).round(2)
    @peak_day = @daily_responses.max_by { |_date, count| count }

    @surveys_summary = current_customer.surveys
                                       .left_joins(:submissions)
                                       .group("surveys.id, surveys.title, surveys.status")
                                       .select("surveys.id, surveys.title, surveys.status, COUNT(submissions.id) AS submissions_count")
                                       .order("submissions_count DESC")
  end
end
