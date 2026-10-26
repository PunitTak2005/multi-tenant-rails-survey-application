class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :current_customer, :logged_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_customer
    @current_customer ||= current_user&.customer
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    unless logged_in?
      flash[:alert] = "You must log in to access this page."
      redirect_to login_path
    end
  end
end
