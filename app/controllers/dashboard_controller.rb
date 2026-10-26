class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @customer = current_customer
    @total_surveys = current_customer.surveys.count
    @published_surveys = current_customer.surveys.published.count
    @draft_surveys = current_customer.surveys.draft.count
    @total_submissions = current_customer.submissions.count
    @recent_surveys = current_customer.surveys.recent.limit(5).includes(:questions, :submissions)
  end
end
