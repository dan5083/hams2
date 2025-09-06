# app/controllers/works_orders_controller.rb - Fixed pricing parameter handling and route card operations
class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :create_invoice]

  def index
    @works_orders = WorksOrder.includes(:customer_order, :part, :release_level, :transport_method)
                              .active
                              .order(created_at: :desc)

    # Add filtering if needed
    if params[:customer_id].present?
      @works_orders = @works_orders.for_customer(params[:customer_id])
    end

    if params[:status] == 'open'
      @works_orders = @works_orders.open
    elsif params[:status] == 'closed'
      @works_orders = @works_orders.closed
    end
  end

  def show
  end

  def new
    # Prevent browser caching
    response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'

    @works_order = WorksOrder.new

    # If coming from nested route, pre-select the customer order
    if params[:customer_order_id].present?
      @customer_order = CustomerOrder.find(params[:customer_order_id])
      @works_order.customer_order = @customer_order
      @customer_orders = [@customer_order]
    else
      @customer_orders = CustomerOrder.active.includes(:customer).order(created_at: :desc)
      @customer_order = nil
    end

    load_reference_data
  end

  def create
    @works_order = WorksOrder.new(works_order_params)

    # If customer_order_id is missing, try to get it from the route
    if @works_order.customer_order_id.blank? && params[:customer_order_id].present?
      @works_order.customer_order_id = params[:customer_order_id]
    end

    # Set up the part automatically
    if setup_part(@works_order)
      if @works_order.save
        redirect_to @works_order, notice: 'Works order was successfully created.'
      else
        load_form_data_for_errors
        render :new, status: :unprocessable_entity
      end
    else
      load_form_data_for_errors
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customer_orders = [@works_order.customer_order] # For edit, just show the current customer order
    load_reference_data
  end

  def update
    # For updates, we might need to update the part if part details changed
    if part_details_changed?
      setup_part(@works_order)
    end

    if @works_order.update(works_order_params)
      redirect_to @works_order, notice: 'Works order was successfully updated.'
    else
      load_reference_data
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @works_order.can_be_deleted?
      @works_order.destroy
      redirect_to works_orders_url, notice: 'Works order was successfully deleted.'
    else
      redirect_to @works_order, alert: 'Cannot delete works order with associated release notes.'
    end
  end

  def route_card
    # Get operations from the works order (which delegates to the part)
    operations_data = @works_order.operations_with_auto_ops || []

    # Transform operations into the format expected by route card templates
    @operations = operations_data.map.with_index(1) do |operation, index|
      next unless operation

      {
        number: index,
        content: [
          {
            type: "paragraph",
            as_html: operation.operation_text || operation.display_name || "Operation #{index}"
          }
        ],
        all_variables: []
      }
    end.compact

    Rails.logger.info "Route Card: Generated #{@operations.length} operations for WO#{@works_order.number}"

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        pdf = Grover.new(
          render_to_string(
            template: 'works_orders/route_card',
            layout: false,
            locals: { works_order: @works_order, operations: @operations }
          ),
          format: 'A4',
          margin: { top: '1cm', bottom: '0.5cm', left: '0.5cm', right: '0.5cm' },
          print_background: true,
          prefer_css_page_size: true,
          emulate_media: 'print'
        ).to_pdf

        send_data pdf,
                  filename: "route_card_wo#{@works_order.number}.pdf",
                  type: 'application/pdf',
                  disposition: 'inline'
      end
    end
  end

  def create_invoice
    Rails.logger.info "🚀 STAGE_INVOICE: Starting for WO#{@works_order.number}"

    if @works_order.quantity_released <= 0
      Rails.logger.info "❌ STAGE_INVOICE: No quantity released (#{@works_order.quantity_released})"
      redirect_to @works_order, alert: 'No items available to invoice - no quantity has been released yet.'
      return
    end

    begin
      # Get all uninvoiced release notes for this works order
      uninvoiced_release_notes = @works_order.release_notes.requires_invoicing
      Rails.logger.info "🔍 STAGE_INVOICE: Found #{uninvoiced_release_notes.count} uninvoiced release notes"

      uninvoiced_release_notes.each do |rn|
        Rails.logger.info "  - RN#{rn.number}: #{rn.quantity_accepted} accepted, can_be_invoiced=#{rn.can_be_invoiced?}"
      end

      if uninvoiced_release_notes.empty?
        Rails.logger.info "❌ STAGE_INVOICE: No uninvoiced release notes found"
        redirect_to @works_order, alert: 'No release notes available for invoicing.'
        return
      end

      # Create local invoice from release notes (no Xero sync)
      customer = @works_order.customer
      Rails.logger.info "🔍 STAGE_INVOICE: Customer: #{customer.name} (ID: #{customer.id})"

      Rails.logger.info "🔍 STAGE_INVOICE: Calling Invoice.create_from_release_notes..."
      invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

      if invoice.nil?
        Rails.logger.error "❌ STAGE_INVOICE: Invoice.create_from_release_notes returned nil"
        redirect_to @works_order, alert: 'Failed to create local invoice from release notes. Check logs for details.'
        return
      end

      Rails.logger.info "✅ STAGE_INVOICE: Local invoice INV#{invoice.number} created successfully"

      redirect_to @works_order,
                  notice: "✅ Invoice INV#{invoice.number} staged successfully! " \
                          "Staged #{uninvoiced_release_notes.count} release note(s) " \
                          "for #{uninvoiced_release_notes.sum(:quantity_accepted)} parts. " \
                          "Go to the dashboard to push invoices to Xero."

    rescue StandardError => e
      Rails.logger.error "💥 STAGE_INVOICE: Exception occurred: #{e.message}"
      Rails.logger.error "💥 STAGE_INVOICE: Backtrace: #{e.backtrace.first(10).join("\n")}"

      redirect_to @works_order,
                  alert: "❌ Failed to stage invoice: #{e.message}. Please try again or contact support."
    end
  end

  # Add these methods to WorksOrdersController (app/controllers/works_orders_controller.rb)

  # NEW: Enhanced invoice creation with additional charges
  def create_invoice_with_charges
    Rails.logger.info "🚀 STAGE_INVOICE_WITH_CHARGES: Starting for WO#{@works_order.number}"

    if @works_order.quantity_released <= 0
      redirect_to @works_order, alert: 'No items available to invoice - no quantity has been released yet.'
      return
    end

    # Get uninvoiced release notes
    uninvoiced_release_notes = @works_order.release_notes.requires_invoicing
    if uninvoiced_release_notes.empty?
      redirect_to @works_order, alert: 'No release notes available for invoicing.'
      return
    end

    begin
      customer = @works_order.customer

      # Create invoice from release notes
      invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

      if invoice.nil?
        redirect_to @works_order, alert: 'Failed to create invoice from release notes.'
        return
      end

      # Add additional charges if any were selected
      if params[:additional_charge_ids].present?
        add_additional_charges_to_invoice(invoice, params[:additional_charge_ids], params[:custom_amounts] || {})
      end

      # Recalculate totals after adding charges
      invoice.calculate_totals!

      redirect_to @works_order,
                  notice: "Invoice INV#{invoice.number} created successfully! " \
                          "#{build_invoice_summary(uninvoiced_release_notes, params[:additional_charge_ids])}"

    rescue StandardError => e
      Rails.logger.error "💥 STAGE_INVOICE_WITH_CHARGES: Exception: #{e.message}"
      redirect_to @works_order, alert: "Failed to create invoice: #{e.message}"
    end
  end


  private

  # Add additional charges to an existing invoice
  def add_additional_charges_to_invoice(invoice, charge_ids, custom_amounts)
    charge_ids.each do |charge_id|
      charge = AdditionalChargePreset.find(charge_id)
      custom_amount = custom_amounts[charge_id]

      InvoiceItem.create_from_additional_charge(charge, invoice, custom_amount)
      Rails.logger.info "✅ Added additional charge: #{charge.name}"
    end
  end

  # Build summary message for invoice creation
  def build_invoice_summary(release_notes, additional_charge_ids)
    summary = "Invoiced #{release_notes.count} release note(s) for #{release_notes.sum(:quantity_accepted)} parts"

    if additional_charge_ids.present?
      charge_count = additional_charge_ids.length
      summary += " with #{charge_count} additional charge(s)"
    end

    summary + ". Go to dashboard to push to Xero."
  end

  # Load additional charge presets for forms
  def load_additional_charges
    @additional_charge_presets = AdditionalChargePreset.enabled.ordered
  end

  def set_works_order
    @works_order = WorksOrder.find(params[:id])
  end

  # UPDATED: Smart parameter filtering based on price_type
  def works_order_params
    # Always allow these core parameters
    permitted_params = [
      :customer_order_id, :part_id, :quantity, :price_type,
      :part_number, :part_issue, :part_description,
      :release_level_id, :transport_method_id
    ]

    # Only permit the relevant price field based on price_type
    price_type = params[:works_order][:price_type]
    Rails.logger.info "🔢 PRICING PARAMS: price_type = #{price_type}"

    case price_type
    when 'each'
      permitted_params << :each_price
      Rails.logger.info "🔢 PRICING PARAMS: Permitting each_price only"
    when 'lot'
      permitted_params << :lot_price
      Rails.logger.info "🔢 PRICING PARAMS: Permitting lot_price only"
    else
      # Default case - allow both for backward compatibility, but log warning
      Rails.logger.warn "🔢 PRICING PARAMS: Unknown price_type '#{price_type}', allowing both price fields"
      permitted_params += [:each_price, :lot_price]
    end

    filtered_params = params.require(:works_order).permit(*permitted_params)
    Rails.logger.info "🔢 PRICING PARAMS: Filtered params = #{filtered_params.to_h}"

    filtered_params
  end

  def load_reference_data
    @release_levels = ReleaseLevel.enabled.ordered
    @transport_methods = TransportMethod.enabled.ordered

    if @customer_order.present?
      Rails.logger.info "🔍 Loading parts for customer: #{@customer_order.customer.name} (ID: #{@customer_order.customer.id})"

      @parts = Part.enabled
                  .for_customer(@customer_order.customer)
                  .includes(:customer)
                  .order(:uniform_part_number)

      Rails.logger.info "🔍 Found #{@parts.count} parts in controller"
      Rails.logger.info "🔍 Part IDs: #{@parts.pluck(:id)}"

      # Force query execution and count from database
      db_count = Part.enabled.for_customer(@customer_order.customer).count
      Rails.logger.info "🔍 Direct DB count: #{db_count}"
    else
      @parts = Part.enabled
                  .includes(:customer)
                  .order(:uniform_part_number)
    end
  end

  def load_form_data_for_errors
    if params[:customer_order_id].present?
      @customer_order = CustomerOrder.find(params[:customer_order_id])
      @customer_orders = [@customer_order]
    elsif @works_order.customer_order.present?
      @customer_order = @works_order.customer_order
      @customer_orders = [@customer_order]
    else
      @customer_order = nil
      @customer_orders = CustomerOrder.active.includes(:customer).order(created_at: :desc)
    end
    load_reference_data
  end

  def setup_part(works_order)
    return false unless works_order.customer_order && works_order.part_id.present?

    customer = works_order.customer_order.customer

    begin
      # Get the selected part
      part = Part.find(works_order.part_id)
      works_order.part = part
      works_order.part_number = part.uniform_part_number
      works_order.part_issue = part.uniform_part_issue
      works_order.part_description = part.description || "#{part.uniform_part_number} component"

      # Check if part has processing instructions configured
      if part.customisation_data.blank? || part.customisation_data.dig("operation_selection", "treatments").blank?
        works_order.errors.add(:part_id, "Part #{part.display_name} does not have processing instructions configured. Please set up this part properly first.")
        return false
      end

      return true
    rescue => e
      works_order.errors.add(:base, "Error setting up part: #{e.message}")
      return false
    end
  end

  def part_details_changed?
    @works_order.part_number_changed? || @works_order.part_issue_changed?
  end


end
