class Question < ApplicationRecord
  belongs_to :survey
  has_many :question_options, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :question
  has_many :answers, dependent: :destroy

  accepts_nested_attributes_for :question_options, allow_destroy: true, reject_if: :all_blank

  enum :question_type, { text: 0, number: 1, multiple_choice: 2 }, default: :text

  validates :question_text, presence: true
  validates :question_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validate :validate_options_for_question_type

  private

  def validate_options_for_question_type
    if !multiple_choice? && question_options.reject(&:marked_for_destruction?).any?
      errors.add(:question_options, "can only be added to multiple choice questions")
    end
  end
end
