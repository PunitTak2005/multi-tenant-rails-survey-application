class Submission < ApplicationRecord
  belongs_to :survey
  has_many :answers, dependent: :destroy, inverse_of: :submission

  validates :submitted_at, presence: true
  validates :respondent_token_digest, uniqueness: { scope: :survey_id, allow_nil: true }

  before_validation :set_submitted_at, on: :create
  after_commit :enqueue_daily_metric_update, on: :create

  scope :recent, -> { order(submitted_at: :desc) }

  private

  def set_submitted_at
    self.submitted_at ||= Time.current
  end

  def enqueue_daily_metric_update
    date_val = (submitted_at || Time.current).to_date.to_s
    UpdateSurveyDailyMetricJob.perform_later(survey_id, date_val)
  end
end
