class ApplicationController < ActionController::Base
  include Authentication

  # Prevent caching of authenticated pages to avoid stale dropdown data
  before_action :set_cache_headers

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def set_cache_headers
    # Prevent browser and proxy caching of dynamic content
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end

  # ============================================================================
  # ROLE-BASED ACCESS CONTROL METHODS
  # ============================================================================

  # Require Xero integration access for invoice and financial features
  def require_xero_access
    unless Current.user&.sees_xero_integration?
      Rails.logger.warn "Unauthorized Xero access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access Xero integration features."
      return false
    end
    true
  end

  # Helper method to check if user has quality/NCR access
  def require_quality_access
    quality_users = [
      'chris@hardanodisingstl.com',
      'quality@hardanodisingstl.com',
      'phil@hardanodisingstl.com',
      'tariq@hardanodisingstl.com',
      'daniel@hardanodisingstl.com'
    ]

    unless Current.user&.email_address&.in?(quality_users)
      Rails.logger.warn "Unauthorized quality/NCR access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access quality management features."
      return false
    end
    true
  end

  # NCR-specific guards (split read vs manage)
  def require_ncr_manage_access
    unless Current.user&.can_manage_ncrs?
      Rails.logger.warn "Unauthorized NCR manage attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to manage NCRs."
      return false
    end
    true
  end

  def require_artifacts_access
    artifacts_users = [
      'daniel@hardanodisingstl.com',
      'julia@hardanodisingstl.com',
      'sophie@hardanodisingstl.com',
      'tariq@hardanodisingstl.com'
    ]

    unless Current.user&.email_address&.in?(artifacts_users)
      Rails.logger.warn "Unauthorized artifacts access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access system configuration."
      return false
    end
    true
  end

  # Helper method to check if user has parts management access
  def require_parts_access
    parts_users = [
      'chris@hardanodisingstl.com',
      'chris.bayliss@hardanodisingstl.com',
      'daniel@hardanodisingstl.com',
      'julia@hardanodisingstl.com',
      'phil@hardanodisingstl.com',
      'quality@hardanodisingstl.com',
      'sophie@hardanodisingstl.com',
      'tariq@hardanodisingstl.com',
      'nigel@hardanodisingstl.com',
      'brian@hardanodisingstl.com',
      'gary@hardanodisingstl.com',
      'gio@hardanodisingstl.com'
    ]

    unless Current.user&.email_address&.in?(parts_users)
      Rails.logger.warn "Unauthorized parts access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access parts management."
      return false
    end
    true
  end

  # Helper method to check if user has developer/admin access
  def require_developer_access
    unless Current.user&.email_address == 'daniel@hardanodisingstl.com'
      Rails.logger.warn "Unauthorized developer access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access developer features."
      return false
    end
    true
  end
end
