class Customer < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :surveys, dependent: :destroy
  has_many :submissions, through: :surveys
  has_many :survey_daily_metrics, through: :surveys, source: :daily_metrics

  validates :name, presence: true
end
