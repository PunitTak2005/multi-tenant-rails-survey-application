class SubmitSurvey
  Result = Struct.new(:success?, :submission, :errors, keyword_init: true)

  def initialize(survey, answer_params, respondent_token_digest: nil)
    @survey = survey
    @answer_params = answer_params || {}
    @respondent_token_digest = respondent_token_digest
  end

  def call
    unless @survey.published?
      return Result.new(success?: false, submission: nil, errors: [ "This survey is not published." ])
    end

    if @survey.limit_one_response_per_device? && @respondent_token_digest.present? &&
       @survey.submissions.exists?(respondent_token_digest: @respondent_token_digest)
      return Result.new(
        success?: false,
        submission: nil,
        errors: [ "You have already submitted this survey from this browser." ]
      )
    end

    submission = nil

    ActiveRecord::Base.transaction do
      submission = @survey.submissions.build(
        submitted_at: Time.current,
        respondent_token_digest: @respondent_token_digest
      )

      @survey.questions.includes(:question_options).each do |question|
        raw_val = @answer_params[question.id.to_s]

        if question.required? && raw_val.blank?
          submission.errors.add(:base, "Question '#{question.question_text}' is required.")
        end

        next if raw_val.blank?

        answer = submission.answers.build(question: question)

        case question.question_type.to_sym
        when :text
          answer.text_value = raw_val.to_s.strip
        when :number
          num_str = raw_val.to_s.strip
          if num_str !~ /\A-?\d+(\.\d+)?\z/
            submission.errors.add(:base, "Answer for '#{question.question_text}' must be a valid number.")
          else
            answer.number_value = BigDecimal(num_str)
          end
        when :multiple_choice
          option_id = raw_val.to_i
          valid_option = question.question_options.find { |opt| opt.id == option_id }
          if valid_option.nil?
            submission.errors.add(:base, "Selected option for '#{question.question_text}' is invalid.")
          else
            answer.selected_option = valid_option
          end
        end
      end

      if submission.errors.any?
        raise ActiveRecord::Rollback
      end

      begin
        unless submission.save
          raise ActiveRecord::Rollback
        end
      rescue ActiveRecord::RecordNotUnique
        submission.errors.add(:base, "You have already submitted this survey from this browser.")
        raise ActiveRecord::Rollback
      end
    end

    if submission&.persisted?
      Result.new(success?: true, submission: submission, errors: [])
    else
      err_messages = submission&.errors&.full_messages || [ "Submission could not be completed." ]
      Result.new(success?: false, submission: nil, errors: err_messages)
    end
  end
end
