class SessionsController < ApplicationController
  def new
    redirect_to dashboard_path if logged_in?
  end

  def create
    user = User.find_by(email: params[:email]&.to_s&.strip&.downcase)

    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      flash[:notice] = "Welcome back, #{user.name}!"
      redirect_to dashboard_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    flash[:notice] = "You have been logged out successfully."
    redirect_to login_path
  end
end
