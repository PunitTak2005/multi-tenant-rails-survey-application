class SurveysController < ApplicationController
  before_action :authenticate_user!
  before_action :set_survey, only: %i[show edit update destroy publish]

  def index
    @surveys = current_customer.surveys.recent.includes(:questions, :submissions)
  end

  def show
    @questions = @survey.questions.includes(:question_options)
    @submissions_count = @survey.submissions.count
  end

  def new
    @survey = current_customer.surveys.build
    question = @survey.questions.build(position: 1, question_type: :text)
  end

  def create
    @survey = current_customer.surveys.build(survey_params)

    if @survey.save
      redirect_to survey_path(@survey), notice: "Survey '#{@survey.title}' was created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @survey.questions.build(position: @survey.questions.size + 1) if @survey.questions.empty?
  end

  def update
    if @survey.update(survey_params)
      redirect_to survey_path(@survey), notice: "Survey '#{@survey.title}' was updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @survey.title
    @survey.destroy
    redirect_to surveys_path, notice: "Survey '#{title}' was deleted successfully."
  end

  def publish
    if @survey.publish!
      redirect_to survey_path(@survey), notice: "Survey was published successfully! It is now accessible via the public link."
    else
      error_message = @survey.errors.full_messages.to_sentence.presence || "Survey could not be published."
      redirect_to survey_path(@survey), alert: error_message
    end
  end

  private

  def set_survey
    @survey = current_customer.surveys.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to surveys_path, alert: "Survey not found."
  end

  def survey_params
    params.require(:survey).permit(
      :title,
      :description,
      :limit_one_response_per_device,
      questions_attributes: [
        :id,
        :question_text,
        :question_type,
        :position,
        :required,
        :_destroy,
        { question_options_attributes: %i[id label position _destroy] }
      ]
    )
  end
end
