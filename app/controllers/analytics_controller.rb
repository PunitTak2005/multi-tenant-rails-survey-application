# frozen_string_literal: true

class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  PRESET_RANGES = %w[30d 90d ytd all].freeze

  def index
    resolve_date_range

    @days_count = [ (@end_date - @start_date).to_i + 1, 1 ].max

    # Read pre-aggregated daily metrics strictly scoped to current_customer.
    # No full-table scans or expensive group-by aggregations on raw submissions table.
    metrics_scope = current_customer.survey_daily_metrics.where(date: @start_date..@end_date)

    @daily_responses = metrics_scope.group(:date)
                                   .order(date: :desc)
                                   .sum(:response_count)

    @total_responses = @daily_responses.values.sum
    @active_days_count = @daily_responses.count
    divisor = @selected_range == "90d" ? 90 : (@selected_range == "30d" ? 30 : @days_count)
    @average_daily_responses = (@total_responses.to_f / divisor).round(2)
    @peak_day = @daily_responses.max_by { |_date, count| count }

    # Per-survey response counts within the selected window
    survey_counts = metrics_scope.group(:survey_id).sum(:response_count)

    @surveys_summary = current_customer.surveys.select(:id, :title, :status).map do |survey|
      count = survey_counts[survey.id] || 0
      survey.define_singleton_method(:submissions_count) { count }
      survey
    end.sort_by { |s| -s.submissions_count }

    configure_ui_labels
  end

  private

  def resolve_date_range
    if params[:start_date].present? || params[:end_date].present?
      parse_custom_date_range
    else
      parse_preset_date_range
    end
  end

  def parse_custom_date_range
    if params[:start_date].blank? || params[:end_date].blank?
      set_default_range
      flash.now[:alert] = "Both start date and end date are required for a custom range. Showing default 90 days."
      return
    end

    s_date = Date.iso8601(params[:start_date].to_s.strip)
    e_date = Date.iso8601(params[:end_date].to_s.strip)

    if s_date > e_date
      set_default_range
      flash.now[:alert] = "Start date must be on or before end date. Showing default 90 days."
      return
    end

    @selected_range = "custom"
    @start_date = s_date
    @end_date = e_date
  rescue Date::Error, ArgumentError
    set_default_range
    flash.now[:alert] = "Invalid date format provided. Showing default 90 days."
  end

  def parse_preset_date_range
    range_param = params[:range].to_s.downcase

    case range_param
    when "30d"
      @selected_range = "30d"
      @start_date = 30.days.ago.to_date
      @end_date = Date.current
    when "ytd"
      @selected_range = "ytd"
      @start_date = Date.current.beginning_of_year
      @end_date = Date.current
    when "all"
      @selected_range = "all"
      earliest = current_customer.survey_daily_metrics.minimum(:date)
      @start_date = earliest || 90.days.ago.to_date
      @end_date = Date.current
    else
      # Default: 90 days (covers range="90d", blank, or invalid string like "banana")
      set_default_range
    end
  end

  def set_default_range
    @selected_range = "90d"
    @start_date = 90.days.ago.to_date
    @end_date = Date.current
  end

  def configure_ui_labels
    case @selected_range
    when "30d"
      @range_label = "over the last 30 days"
      @total_label = "Total 30-Day Responses"
      @empty_state_title = "No response data in the last 30 days"
      @timeline_title = "Daily Response Volume (Past 30 Days)"
      @timeline_desc = "Timeline (30 Days)"
    when "ytd"
      @range_label = "for year to date"
      @total_label = "Total YTD Responses"
      @empty_state_title = "No response data for the year to date"
      @timeline_title = "Daily Response Volume (Year to Date)"
      @timeline_desc = "Timeline (YTD)"
    when "all"
      @range_label = "across all time"
      @total_label = "Total All-Time Responses"
      @empty_state_title = "No response data across all time"
      @timeline_title = "Daily Response Volume (All Time)"
      @timeline_desc = "Timeline (All Time)"
    when "custom"
      @range_label = "for #{@start_date.strftime('%b %d, %Y')} to #{@end_date.strftime('%b %d, %Y')}"
      @total_label = "Total Period Responses"
      @empty_state_title = "No response data for the selected date range"
      @timeline_title = "Daily Response Volume (Custom Range)"
      @timeline_desc = "Timeline (#{@days_count} Days)"
    else
      @range_label = "over the last 90 days"
      @total_label = "Total 90-Day Responses"
      @empty_state_title = "No response data in the last 90 days"
      @timeline_title = "Daily Response Volume (Past 90 Days)"
      @timeline_desc = "Timeline (90 Days)"
    end
  end
end
