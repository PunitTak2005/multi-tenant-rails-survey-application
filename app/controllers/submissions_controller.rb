class SubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_survey

  def index
    @submissions = @survey.submissions.recent.includes(answers: %i[question selected_option])
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
end
