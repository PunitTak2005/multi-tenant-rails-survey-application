class Survey < ApplicationRecord
  belongs_to :customer
  has_many :questions, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :survey
  has_many :submissions, dependent: :destroy
  has_many :answers, through: :submissions
  has_many :daily_metrics, class_name: "SurveyDailyMetric", dependent: :destroy

  accepts_nested_attributes_for :questions, allow_destroy: true, reject_if: :all_blank

  enum :status, { draft: 0, published: 1 }, default: :draft

  before_validation :ensure_public_token, on: :create

  validates :title, presence: true
  validates :status, presence: true
  validates :public_token, presence: true, uniqueness: true
  validates :limit_one_response_per_device, inclusion: { in: [ true, false ] }

  scope :recent, -> { order(created_at: :desc) }

  def self.respondent_token_digest(survey_id, token)
    return nil if token.blank? || survey_id.blank?

    Digest::SHA256.hexdigest("#{survey_id}:#{token}")
  end

  def publishable?
    errors.clear
    errors.add(:base, "Survey must have at least one question to be published.") if questions.reload.empty?

    questions.each do |q|
      if q.multiple_choice? && q.question_options.reload.empty?
        errors.add(:base, "Multiple choice question '#{q.question_text.truncate(30)}' must have at least one option.")
      end
    end

    errors.empty?
  end

  def publish!
    if publishable?
      update!(status: :published, published_at: Time.current)
    else
      false
    end
  end

  private

  def ensure_public_token
    self.public_token ||= SecureRandom.urlsafe_base64(16)
  end
end
