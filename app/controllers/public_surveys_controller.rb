class PublicSurveysController < ApplicationController
  # Public survey access does not require authentication
  skip_before_action :verify_authenticity_token, only: [] # CSRF is enabled
  rescue_from ActiveRecord::RecordNotFound, with: :survey_not_found

  # Rate limiting on unauthenticated public endpoints
  rate_limit to: 60, within: 1.minute,
             by: -> { "#{request.remote_ip}:#{params[:public_token]}" },
             with: :render_rate_limited,
             only: %i[show success]

  rate_limit to: 10, within: 1.minute,
             by: -> { "#{request.remote_ip}:#{params[:public_token]}" },
             with: :render_rate_limited,
             only: :submit

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

  def render_rate_limited
    response.set_header("Retry-After", "60")
    respond_to do |format|
      format.html do
        render file: Rails.public_path.join("429.html"), status: :too_many_requests, layout: false
      rescue StandardError
        render plain: "Too Many Requests. Please wait 60 seconds before retrying.", status: :too_many_requests
      end
      format.json do
        render json: { error: "Too Many Requests", message: "Rate limit exceeded. Please wait 60 seconds before retrying." },
               status: :too_many_requests
      end
      format.any do
        head :too_many_requests
      end
    end
  end
end
