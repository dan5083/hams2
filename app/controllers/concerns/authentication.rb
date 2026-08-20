module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :refresh_sub_user
    helper_method :authenticated?, :sub_user_signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :refresh_sub_user, **options
    end

    # Opt-in gate for actions that must be attributed to a named operator
    # rather than to whoever left the terminal logged in.
    def require_sub_user(**options)
      before_action :require_sub_user_session, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def sub_user_signed_in?
      Current.sub_user.present?
    end

    def require_authentication
      Rails.logger.info "=== AUTH: require_authentication called for #{request.path} ==="
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    # Either the unlock has gone stale and gets dropped, or it's live and the
    # clock is nudged forward. Runs on every authenticated request.
    def refresh_sub_user
      session_record = Current.session
      return if session_record.nil? || session_record.sub_user_id.blank?

      if session_record.sub_user_expired?
        Rails.logger.info "=== SUB-USER: unlock expired for session #{session_record.id} ==="
        session_record.end_sub_user!
      else
        session_record.touch_sub_user!
      end
    end

    def require_sub_user_session
      return if Current.sub_user

      redirect_back fallback_location: root_path,
                    alert: "Unlock as an operator before signing anything on this works order."
    end

    def request_authentication
      Rails.logger.info "=== AUTH: request_authentication called - redirecting to login ==="
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
