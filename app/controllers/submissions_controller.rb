class SubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_survey

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

  def show
    @submission = @survey.submissions.find(params[:id])
    existing_answers = @submission.answers.includes(:question, :selected_option).index_by(&:question_id)
    @answers = @survey.questions.order(:position).includes(:question_options).map do |question|
      existing_answers[question.id] || @submission.answers.build(question: question)
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to survey_submissions_path(@survey), alert: "Submission not found."
  end

  private

  def set_survey
    @survey = current_customer.surveys.find(params[:survey_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to surveys_path, alert: "Survey not found."
  end

  def sanitize_page(val)
    return 1 if val.blank?
    str = val.to_s.strip
    return 1 unless str =~ /\A\d+\z/

    [ str.to_i, 1 ].max
  end

  def sanitize_limit(val)
    return DEFAULT_PER_PAGE if val.blank?
    str = val.to_s.strip
    return DEFAULT_PER_PAGE unless str =~ /\A\d+\z/

    [ [ str.to_i, 1 ].max, MAX_PER_PAGE ].min
  end
end
