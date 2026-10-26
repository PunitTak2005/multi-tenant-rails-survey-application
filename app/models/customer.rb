class Customer < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :surveys, dependent: :destroy
  has_many :submissions, through: :surveys

  validates :name, presence: true
end
