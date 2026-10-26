class QuestionOption < ApplicationRecord
  belongs_to :question
  has_many :answers, foreign_key: :selected_option_id, dependent: :nullify

  validates :label, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validate :question_must_be_multiple_choice

  private

  def question_must_be_multiple_choice
    if question && !question.multiple_choice?
      errors.add(:question, "must be multiple choice to have options")
    end
  end
end
