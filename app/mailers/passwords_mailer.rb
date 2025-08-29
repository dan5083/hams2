class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "Reset your password", to: user.email_address
  end

  def magic_link(user, token)
    @user = user
    @magic_link_url = magic_link_url(token)
    mail subject: "Your login link for HAMS", to: user.email_address
  end
end
