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

  # Require e-card access for shop floor and manufacturing features
  def require_ecard_access
    unless Current.user&.sees_ecards?
      Rails.logger.warn "Unauthorized e-card access attempt by #{Current.user&.email_address || 'unknown user'} on #{request.path}"
      redirect_to root_path, alert: "You don't have permission to access e-cards."
      return false
    end
    true
  end

  # Check if current user can see a specific work order based on their filter criteria
  def user_can_see_work_order?(work_order)
    return true unless Current.user&.sees_ecards? # If they can't see e-cards, don't filter

    filter_criteria = Current.user.ecard_filter_criteria
    return true if filter_criteria.blank? # No filtering = see everything

    part = work_order.part
    return true unless part # If no part, allow access

    operations = part.get_operations_with_auto_ops

    # Check basic access restriction (for maintenance staff)
    if filter_criteria[:basic_access_only]
      return false # Maintenance gets basic access only, no e-card filtering
    end

    # Aerospace priority filtering
    if filter_criteria[:aerospace_priority] && part.aerospace_defense?
      return true # Quality staff see aerospace work first
    end

    # VAT number filtering
    if filter_criteria[:vat_numbers].present?
      operation_vats = operations.flat_map(&:vat_numbers).uniq
      return false if operation_vats.any? && (operation_vats & filter_criteria[:vat_numbers]).empty?
    end

    # Process type filtering (include specific types)
    if filter_criteria[:process_types].present?
      operation_process_types = operations.map(&:process_type).uniq
      return false if (operation_process_types & filter_criteria[:process_types]).empty?
    end

    # Process type exclusion filtering
    if filter_criteria[:exclude_process_types].present?
      operation_process_types = operations.map(&:process_type).uniq
      return false if (operation_process_types & filter_criteria[:exclude_process_types]).any?
    end

    # Priority process types (show these first, but don't exclude others)
    if filter_criteria[:priority_process_types].present?
      operation_process_types = operations.map(&:process_type).uniq
      # This would be used for sorting, not filtering
    end

    true # Default to allowing access
  end

  # Apply user-specific filtering to works orders collection
  def apply_user_work_order_filtering(works_orders)
    return works_orders unless Current.user&.sees_ecards?

    filter_criteria = Current.user.ecard_filter_criteria
    return works_orders if filter_criteria.blank?

    # For basic access only (maintenance), return empty collection
    if filter_criteria[:basic_access_only]
      return works_orders.none
    end

    # If user sees everything (management, quality inspectors, contract reviewers)
    if filter_criteria[:description]&.include?("sees all")
      return works_orders
    end

    # Apply filtering based on parts and operations
    filtered_ids = works_orders.includes(:part).select do |work_order|
      user_can_see_work_order?(work_order)
    end.map(&:id)

    works_orders.where(id: filtered_ids)
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
