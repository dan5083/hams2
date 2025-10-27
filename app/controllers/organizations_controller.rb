# app/controllers/organizations_controller.rb
class OrganizationsController < ApplicationController
  def index
    @customers = Organization.customers
                            .enabled
                            .includes(:buyers, :xero_contact)
                            .order(:name)

    @suppliers = Organization.suppliers
                            .enabled
                            .includes(:xero_contact)
                            .order(:name)
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
