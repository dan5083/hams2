# app/controllers/organizations_controller.rb
class OrganizationsController < ApplicationController
  def index
    # Start with base query
    @organizations = Organization.includes(:buyers, :xero_contact)

    # Filter by type (customers/suppliers)
    case params[:type]
    when 'customers'
      @organizations = @organizations.customers
    when 'suppliers'
      @organizations = @organizations.suppliers
    else
      # Show all by default
      @organizations = @organizations
    end

    # Filter by enabled status
    case params[:status]
    when 'enabled'
      @organizations = @organizations.enabled
    when 'disabled'
      @organizations = @organizations.disabled
    else
      # Show enabled by default
      @organizations = @organizations.enabled
    end

    # Filter by buyer presence
    if params[:buyers].present?
      case params[:buyers]
      when 'with_buyers'
        @organizations = @organizations.joins(:buyers).distinct
      when 'without_buyers'
        @organizations = @organizations.left_joins(:buyers)
                                      .where(buyers: { id: nil })
      end
    end

    # Search by organization name
    if params[:search].present?
      @organizations = @organizations.where("name ILIKE ?", "%#{params[:search]}%")
    end

    # Order and paginate
    @organizations = @organizations.order(:name)
                                  .page(params[:page])
                                  .per(20)
  end

  def sync_from_xero
    begin
      Organization.sync_from_xero
      redirect_to organizations_path, notice: 'Successfully synced organizations from Xero.'
    rescue StandardError => e
      Rails.logger.error "Failed to sync from Xero: #{e.message}"
      redirect_to organizations_path, alert: "Failed to sync from Xero: #{e.message}"
    end
  end
end
