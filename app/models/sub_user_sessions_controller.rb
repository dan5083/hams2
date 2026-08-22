class SubUserSessionsController < ApplicationController
  rate_limit to: 20, within: 3.minutes, only: :create,
             with: -> { redirect_back fallback_location: root_path, alert: "Too many PIN attempts. Wait a moment." }

  def create
    # signable rather than enabled: an operator whose staff login has been
    # disabled can no longer be found here, so their PIN dies with the login.
    sub_user = SubUser.signable.find_by(id: params[:sub_user_id])

    unless sub_user
      return redirect_to safe_return_to, alert: "That operator isn't set up.", status: :see_other
    end

    case sub_user.verify_pin(params[:pin])
    when :ok
      Current.session.start_sub_user!(sub_user)
      Rails.logger.info "=== SUB-USER: #{sub_user.name} unlocked on session #{Current.session.id} " \
                        "(account #{Current.user.email_address}, ip #{request.remote_ip}) " \
                        "last_seen=#{Current.session.reload.sub_user_last_seen_at.inspect} ==="
      # No flash. The magenta bar and the name in the corner are the receipt.
      redirect_to safe_return_to, status: :see_other
    when :locked
      Rails.logger.warn "=== SUB-USER: #{sub_user.name} locked out on session #{Current.session.id} ==="
      redirect_to safe_return_to,
                  alert: "#{sub_user.name} is locked out for #{sub_user.lock_expires_in} more minute(s). See Tariq.",
                  status: :see_other
    else
      redirect_to safe_return_to, alert: "Wrong PIN.", status: :see_other
    end
  end

  def destroy
    Current.session.end_sub_user!
    redirect_to safe_return_to, status: :see_other
  end

  private

  # Only ever bounce back to a path on this app - never to whatever a form
  # happens to carry.
  def safe_return_to
    candidate = params[:return_to].to_s
    candidate.start_with?("/") && !candidate.start_with?("//") ? candidate : root_path
  end
end
