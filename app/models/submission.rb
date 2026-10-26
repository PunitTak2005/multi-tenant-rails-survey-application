class Submission < ApplicationRecord
  belongs_to :survey
  has_many :answers, dependent: :destroy, inverse_of: :submission

  validates :submitted_at, presence: true

  before_validation :set_submitted_at, on: :create

  scope :recent, -> { order(submitted_at: :desc) }

  private

  def set_submitted_at
    self.submitted_at ||= Time.current
  end
end
