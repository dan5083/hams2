# app/controllers/skipton_mappings_controller.rb
class SkiptonMappingsController < ApplicationController
  before_action :set_mapping, only: [:edit, :update, :destroy]

  # GET /skipton/mappings
  def index
    @mappings = SkiptonCustomerMapping.order(:xero_name)

    # Search functionality
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @mappings = @mappings.where(
        "xero_name ILIKE ? OR skipton_id ILIKE ?",
        search_term,
        search_term
      )
    end

    # Paginate (20 per page)
    @mappings = @mappings.page(params[:page]).per(20)

    # Count unmapped customers with invoices
    @unmapped_count = SkiptonCustomerMapping.unmapped_invoice_customers.count
  end

  # POST /skipton/mappings
  def create
    @mapping = SkiptonCustomerMapping.new(mapping_params)

    if @mapping.save
      redirect_to skipton_mappings_path, notice: "Mapping added successfully for '#{@mapping.xero_name}'"
    else
      redirect_to skipton_mappings_path, alert: "Failed to add mapping: #{@mapping.errors.full_messages.join(', ')}"
    end
  end

  # POST /skipton/mappings/batch
  def batch_create
    mappings_params = params[:mappings]&.values || []

    if mappings_params.empty?
      redirect_to skipton_exports_path, alert: "No mappings provided"
      return
    end

    created_count = 0
    errors = []

    mappings_params.each do |mapping_data|
      mapping = SkiptonCustomerMapping.new(
        xero_name: mapping_data[:xero_name],
        skipton_id: mapping_data[:skipton_id]
      )

      if mapping.save
        created_count += 1
      else
        errors << "#{mapping.xero_name}: #{mapping.errors.full_messages.join(', ')}"
      end
    end

    if errors.empty?
      redirect_to skipton_exports_path, notice: "✅ Added #{created_count} mapping(s). You can now retry the export."
    else
      redirect_to skipton_exports_path, alert: "Created #{created_count}, but #{errors.count} failed: #{errors.join('; ')}"
    end
  end

  # GET /skipton/mappings/:id/edit
  def edit
    # @mapping set by before_action
  end

  # PATCH /skipton/mappings/:id
  def update
    if @mapping.update(mapping_params)
      redirect_to skipton_mappings_path, notice: "Mapping updated successfully"
    else
      render :edit, alert: "Failed to update: #{@mapping.errors.full_messages.join(', ')}"
    end
  end

  # DELETE /skipton/mappings/:id
  def destroy
    customer_name = @mapping.xero_name
    @mapping.destroy
    redirect_to skipton_mappings_path, notice: "Deleted mapping for '#{customer_name}'"
  end

  private

  def set_mapping
    @mapping = SkiptonCustomerMapping.find(params[:id])
  end

  def mapping_params
    params.require(:skipton_customer_mapping).permit(:xero_name, :skipton_id)
  end
end
