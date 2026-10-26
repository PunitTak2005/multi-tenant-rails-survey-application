class Answer < ApplicationRecord
  belongs_to :submission
  belongs_to :question
  belongs_to :selected_option, class_name: "QuestionOption", optional: true

  validate :validate_value_type_matches_question

  def display_value
    if question.text?
      text_value
    elsif question.number?
      number_value.to_s
    elsif question.multiple_choice?
      selected_option&.label || "No option selected"
    end
  end

  private

  def validate_value_type_matches_question
    return unless question

    case question.question_type.to_sym
    when :text
      if number_value.present? || selected_option_id.present?
        errors.add(:base, "Text questions cannot have number or option values")
      end
      if question.required? && text_value.blank?
        errors.add(:text_value, "is required")
      end
    when :number
      if text_value.present? || selected_option_id.present?
        errors.add(:base, "Number questions cannot have text or option values")
      end
      if question.required? && number_value.blank?
        errors.add(:number_value, "is required")
      end
    when :multiple_choice
      if text_value.present? || number_value.present?
        errors.add(:base, "Multiple choice questions cannot have text or number values")
      end
      if question.required? && selected_option_id.blank?
        errors.add(:selected_option_id, "is required")
      end
      if selected_option_id.present?
        if selected_option.nil? || selected_option.question_id != question_id
          errors.add(:selected_option_id, "must belong to this question")
        end
      end
    end
  end
end
