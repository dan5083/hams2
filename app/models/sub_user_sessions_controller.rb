class SubUserSessionsController < ApplicationController
  # This is the brute-force defence now that failures can't be pinned on an
  # operator. Scoped per terminal via the session cookie, NOT per IP - the
  # whole factory reaches Heroku through one public IP, and a shared budget
  # would jam every terminal at shift start.
  rate_limit to: 20, within: 3.minutes, only: :create,
             by: -> { cookies.signed[:session_id] || request.remote_ip },
             with: -> { redirect_back fallback_location: root_path, alert: "Too many PIN attempts. Wait a moment." }

  def create
    # The PIN is the identity. Lookup is scoped signable inside find_by_pin,
    # so a disabled staff login still kills the operator's PIN with it.
    operator = SubUser.find_by_pin(params[:pin])

    if operator.nil?
      redirect_to safe_return_to, alert: "PIN not recognised.", status: :see_other
    elsif operator.locked?
      Rails.logger.warn "=== SUB-USER: #{operator.name} is manually locked, sign-on refused on session #{Current.session.id} ==="
      redirect_to safe_return_to,
                  alert: "#{operator.name} is locked out for #{operator.lock_expires_in} more minute(s). See Tariq.",
                  status: :see_other
    else
      Current.session.start_sub_user!(operator)
      Rails.logger.info "=== SUB-USER: #{operator.name} unlocked on session #{Current.session.id} " \
                        "(account #{Current.user.email_address}, ip #{request.remote_ip}) " \
                        "last_seen=#{Current.session.reload.sub_user_last_seen_at.inspect} ==="
      # No flash. The magenta bar and the name in the corner are the receipt -
      # doubly important now: a mis-key that lands on a colleague's PIN signs
      # on silently as them, and the name in the corner is how that gets seen.
      redirect_to safe_return_to, status: :see_other
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
