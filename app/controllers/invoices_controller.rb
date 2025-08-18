# app/controllers/invoices_controller.rb
class InvoicesController < ApplicationController
  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :void]

  def index
    @invoices = Invoice.includes(:customer, :invoice_items)
                      .order(created_at: :desc)

    # Filter by sync status
    case params[:status]
    when 'synced'
      @invoices = @invoices.synced
    when 'requiring_sync'
      @invoices = @invoices.requiring_xero_sync
    end

    # Filter by customer
    if params[:customer_id].present?
      @invoices = @invoices.where(customer_id: params[:customer_id])
    end

    # For the filter dropdown
    @customers = Organization.customers.enabled.order(:name)
  end

  def show
  end

  def new
    @invoice = Invoice.new
    @customers = Organization.customers.enabled.order(:name)
  end

  def create
    @invoice = Invoice.new(invoice_params)

    if @invoice.save
      redirect_to @invoice, notice: 'Invoice was successfully created.'
    else
      @customers = Organization.customers.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customers = Organization.customers.enabled.order(:name)
  end

  def update
    if @invoice.update(invoice_params)
      redirect_to @invoice, notice: 'Invoice was successfully updated.'
    else
      @customers = Organization.customers.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @invoice.can_be_deleted?
      @invoice.destroy
      redirect_to invoices_url, notice: 'Invoice was successfully deleted.'
    else
      redirect_to @invoice, alert: 'Cannot delete invoice with associated items.'
    end
  end

  def void
    # Implementation for voiding invoices if needed
    redirect_to @invoice, alert: 'Invoice voiding not yet implemented.'
  end

  # Bulk push selected invoices to Xero
  def push_selected_to_xero
    Rails.logger.info "🚀 BULK_PUSH: Starting bulk push to Xero"

    # Check if any invoices were selected
    invoice_ids = params[:invoice_ids]
    if invoice_ids.blank?
      redirect_to root_path, alert: 'No invoices selected for pushing to Xero.'
      return
    end

    # Check Xero connection
    unless session[:xero_token_set] && session[:xero_tenant_id]
      Rails.logger.info "❌ BULK_PUSH: No Xero connection"
      redirect_to root_path, alert: 'Please connect to Xero first before pushing invoices.'
      return
    end

    begin
      # Get the selected invoices
      invoices = Invoice.requiring_xero_sync
                       .where(id: invoice_ids)
                       .includes(:customer)

      Rails.logger.info "🔍 BULK_PUSH: Found #{invoices.count} invoices to push"

      if invoices.empty?
        redirect_to root_path, alert: 'No valid invoices found for pushing to Xero.'
        return
      end

      # Check all customers have Xero contacts
      missing_contacts = invoices.select { |inv| inv.customer.xero_contact&.xero_id.blank? }
      if missing_contacts.any?
        customer_names = missing_contacts.map { |inv| inv.customer.name }.uniq.join(', ')
        redirect_to root_path,
                    alert: "Cannot push invoices - customers missing Xero contacts: #{customer_names}. Please sync customers from Xero first."
        return
      end

      # Push invoices to Xero using existing service
      Rails.logger.info "🔍 BULK_PUSH: Pushing #{invoices.count} invoices to Xero..."
      xero_service = XeroInvoiceService.new(session[:xero_token_set], session[:xero_tenant_id])

      success_count = 0
      failed_count = 0
      failed_invoices = []

      invoices.each do |invoice|
        Rails.logger.info "🔍 BULK_PUSH: Pushing invoice INV#{invoice.number}..."
        result = xero_service.push_invoice(invoice)

        if result[:success]
          success_count += 1
          Rails.logger.info "✅ BULK_PUSH: Invoice INV#{invoice.number} pushed successfully"
        else
          failed_count += 1
          failed_invoices << "INV#{invoice.number}"
          Rails.logger.error "❌ BULK_PUSH: Invoice INV#{invoice.number} failed: #{result[:error]}"
        end
      end

      # Build success/error message
      if success_count > 0 && failed_count == 0
        redirect_to root_path,
                    notice: "✅ Successfully pushed #{success_count} invoice(s) to Xero!"
      elsif success_count > 0 && failed_count > 0
        redirect_to root_path,
                    alert: "⚠️ Pushed #{success_count} invoice(s) successfully, but #{failed_count} failed: #{failed_invoices.join(', ')}. Please check Xero connection and try again."
      else
        redirect_to root_path,
                    alert: "❌ Failed to push all #{failed_count} invoice(s) to Xero: #{failed_invoices.join(', ')}. Please check Xero connection and try again."
      end

    rescue StandardError => e
      Rails.logger.error "💥 BULK_PUSH: Exception occurred: #{e.message}"
      Rails.logger.error "💥 BULK_PUSH: Backtrace: #{e.backtrace.first(10).join("\n")}"

      redirect_to root_path,
                  alert: "❌ Failed to push invoices to Xero: #{e.message}. Please try again or contact support."
    end
  end



  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(
      :customer_id,
      :date,
      :tax_rate_pct,
      :xero_tax_type
    )
  end
end
