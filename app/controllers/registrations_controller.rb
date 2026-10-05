class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_url, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[first_name last_name email_address password password_confirmation]))
    if @user.save
      start_new_session_for @user
      redirect_to new_report_path, notice: "Welcome to Curb. Check your first car."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
