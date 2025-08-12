# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  # Allow unauthenticated access for registration - people need to sign up!
  allow_unauthenticated_access

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to new_session_path, notice: "Registration successful! Please log in."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :username, :full_name, :password, :password_confirmation)
  end
end
