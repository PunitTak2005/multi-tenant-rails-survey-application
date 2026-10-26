class SubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_survey

  def index
    @submissions = @survey.submissions.recent.includes(answers: %i[question selected_option])
  end

  def show
    @submission = @survey.submissions.find(params[:id])
    @answers = @submission.answers.includes(:question, :selected_option).order("questions.position ASC")
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
