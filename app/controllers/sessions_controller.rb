class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create magic_link ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  def new
  end

  def create
    email = params[:email_address]&.strip&.downcase

    if email.present? && email.match?(/@hardanodisingstl\.com\z/)
      user = User.find_by(email_address: email)

      if user&.active?
        # Generate magic link and send email
        token = user.generate_magic_link_token
        PasswordsMailer.magic_link(user, token).deliver_now

        Rails.logger.info "Magic link sent to #{email}"
      end
    end

    # Always show the same message for security (don't reveal if email exists)
    redirect_to new_session_path, notice: "If that email is authorized, we've sent you a login link. Check your email!"
  end

  def magic_link
    token = params[:token]
    user = User.find_by_magic_link(token)

    if user
      # Clear the magic link token (one-time use)
      user.clear_magic_link!

      # Start session
      start_new_session_for user

      Rails.logger.info "Magic link login successful for #{user.email_address}"
      redirect_to after_authentication_url, notice: "Welcome back, #{user.display_name}!"
    else
      Rails.logger.warn "Invalid or expired magic link attempted: #{token}"
      redirect_to new_session_path, alert: "That login link is invalid or has expired. Please request a new one."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "You've been signed out."
  end
end
