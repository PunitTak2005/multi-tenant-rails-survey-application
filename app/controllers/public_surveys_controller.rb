class PublicSurveysController < ApplicationController
  # Public survey access does not require authentication
  skip_before_action :verify_authenticity_token, only: [] # CSRF is enabled
  rescue_from ActiveRecord::RecordNotFound, with: :survey_not_found

  def show
    @survey = Survey.published.find_by!(public_token: params[:public_token])
    @questions = @survey.questions.includes(:question_options)
  end

  def submit
    @survey = Survey.published.find_by!(public_token: params[:public_token])
    result = SubmitSurvey.new(@survey, params[:answers]).call

    if result.success?
      redirect_to public_survey_success_path(@survey.public_token)
    else
      @errors = result.errors
      flash.now[:alert] = result.errors.to_sentence
      @questions = @survey.questions.includes(:question_options)
      render :show, status: :unprocessable_entity
    end
  end

  def success
    @survey = Survey.published.find_by!(public_token: params[:public_token])
  end

  private

  def survey_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
