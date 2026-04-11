# app/controllers/works_orders_controller.rb - Fixed pricing parameter handling and route card operations with RBAC
class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :ecard, :sign_off_operation, :save_batches, :create_invoice, :void, :unvoid]
  before_action :require_ecard_access, only: [:ecard, :sign_off_operation, :save_batches, :save_operation_input]

 def index
    @works_orders = WorksOrder.includes(:customer_order, :part, customer: [])

    # Search functionality - supports multiple search types
    if params[:search].present?
      search_term = params[:search].strip

      # General search across all fields - works order numbers, part numbers, customer names, and release note numbers
      @works_orders = @works_orders.joins(customer_order: :customer)
                                  .where(
                                    "CAST(works_orders.number AS TEXT) ILIKE ? OR " \
                                    "works_orders.part_number ILIKE ? OR " \
                                    "organizations.name ILIKE ?",
                                    "%#{search_term}%", "%#{search_term}%", "%#{search_term}%"
                                  )

      @works_orders = @works_orders.distinct
    elsif params[:customer_search].present?
      # Legacy customer search (for backwards compatibility)
      customer_search_term = params[:customer_search].strip
      @works_orders = @works_orders.joins(customer_order: :customer)
                                  .where("organizations.name ILIKE ?", "%#{customer_search_term}%")
    elsif params[:customer_id].present?
      @works_orders = @works_orders.for_customer(params[:customer_id])
    end

    # Part filtering (from part show page "View all works orders" link)
    if params[:part_id].present?
      @works_orders = @works_orders.where(part_id: params[:part_id])
    end

    # Status filtering
    if params[:status] == 'open'
      @works_orders = @works_orders.open
    elsif params[:status] == 'closed'
      @works_orders = @works_orders.closed
    end

    # For customer autocomplete - get all customers with active works orders
    # Do this before pagination to get all available customers
    @customers_for_autocomplete = WorksOrder.joins(customer_order: :customer)
                                          .where(voided: false)
                                          .distinct
                                          .pluck('organizations.name')
                                          .sort

    # Order by works order number descending (largest numbers first) and paginate
    @works_orders = @works_orders.order(number: :desc).page(params[:page]).per(20)
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
      Rails.logger.info "🔍 DEBUG: request.format = #{request.format}, params[:works_orders].present? = #{params[:works_orders].present?}"

    # Check if this is a bulk creation request (JSON with works_orders array)
    if request.format.json? && params[:works_orders].present?
      create_bulk
    else
      create_single
    end
  end

  def edit
    @customer_orders = [@works_order.customer_order] # For edit, just show the current customer order
    load_reference_data
  end

  def update
    if @works_order.update(works_order_params)
      redirect_to @works_order, notice: 'Works order was successfully updated.'
    else
      load_form_data_for_errors
      render :edit, status: :unprocessable_entity
    end
  end

  def void
    if @works_order.can_be_voided?
      @works_order.void!
      redirect_to @works_order, notice: 'Works order was successfully voided.'
    else
      redirect_to @works_order, alert: 'Cannot void works order - it has associated release notes.'
    end
  end

  def unvoid
    if @works_order.voided?
      @works_order.unvoid!
      redirect_to @works_order, notice: 'Works order was successfully unvoided and reopened.'
    else
      redirect_to @works_order, alert: 'Works order is not voided.'
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
    # Check if any quantity has been released across the entire customer order
    customer_order = @works_order.customer_order
    total_released = customer_order.works_orders.active.sum(:quantity_released)

    if total_released <= 0
      redirect_to @works_order, alert: 'No items available to invoice - no quantity has been released for this customer order yet.'
      return
    end

    begin
      # Get all uninvoiced release notes for the ENTIRE customer order (not just this works order)
      uninvoiced_release_notes = ReleaseNote.joins(:works_order)
                                          .where(works_orders: { customer_order_id: customer_order.id })
                                          .requires_invoicing

      if uninvoiced_release_notes.empty?
        redirect_to @works_order, alert: 'No release notes available for invoicing across this customer order.'
        return
      end

      # Create invoice from all uninvoiced release notes for this customer order
      customer = customer_order.customer

      invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

      if invoice.nil?
        redirect_to @works_order, alert: 'Failed to create invoice from release notes. Check logs for details.'
        return
      end

      # Add additional charges from ALL works orders in this customer order
      customer_order.works_orders.active.each do |wo|
        if wo.selected_charge_ids.present?
          add_additional_charges_to_invoice(invoice, wo.selected_charge_ids, wo.custom_amounts || {})
        end
      end

      # Recalculate totals after adding all charges
      invoice.calculate_totals!

      redirect_to @works_order,
                  notice: "Invoice INV#{invoice.number} staged successfully! Go to dashboard to push to Xero."

    rescue StandardError => e
      Rails.logger.error "Invoice creation error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      redirect_to @works_order, alert: "Error creating invoice: #{e.message}"
    end
  end

  # E-card view for shop floor
  def ecard
    @operations = @works_order.operations_with_auto_ops || []
    @batches = @works_order.batches.order(created_at: :desc)
  end

  def sign_off_operation
    operation_index = params[:operation_index].to_i
    batch_id = params[:batch_id]

    batch = @works_order.batches.find(batch_id)
    batch.sign_off_operation!(operation_index, Current.user)

    redirect_to ecard_works_order_path(@works_order), notice: "Operation signed off successfully."
  rescue => e
    redirect_to ecard_works_order_path(@works_order), alert: "Error signing off operation: #{e.message}"
  end

  def save_batches
    batch_params = params.require(:batches).permit!
    @works_order.update_batches!(batch_params, Current.user)
    redirect_to ecard_works_order_path(@works_order), notice: "Batches saved successfully."
  rescue => e
    redirect_to ecard_works_order_path(@works_order), alert: "Error saving batches: #{e.message}"
  end

  def save_operation_input
    work_order = WorksOrder.find(params[:id])
    operation_index = params[:operation_index].to_i
    input_data = params[:input_data].permit!

    work_order.save_operation_input!(operation_index, input_data, Current.user)

    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to ecard_works_order_path(work_order), notice: "Input saved." }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to ecard_works_order_path(work_order), alert: "Error: #{e.message}" }
    end
  end

  private

  def create_bulk
    works_orders_params = params[:works_orders]
    results = []

    ActiveRecord::Base.transaction do
      works_orders_params.each do |wo_params|
        wo = WorksOrder.new(
          customer_order_id: wo_params[:customer_order_id],
          part_id: wo_params[:part_id],
          quantity: wo_params[:quantity],
          price_type: wo_params[:price_type],
          each_price: wo_params[:each_price],
          lot_price: wo_params[:lot_price],
          customer_reference: wo_params[:customer_reference]
        )

        if validate_part_configuration(wo) && wo.save
          results << { id: wo.id, number: wo.number, status: 'created' }
        else
          results << { part_id: wo_params[:part_id], status: 'error', errors: wo.errors.full_messages }
        end
      end
    end

    render json: { results: results }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create_single
    @works_order = WorksOrder.new(works_order_params)

    # If customer_order_id is missing, try to get it from the route
    if @works_order.customer_order_id.blank? && params[:customer_order_id].present?
      @works_order.customer_order_id = params[:customer_order_id]
    end

    # Validate part is properly configured
    if validate_part_configuration(@works_order)
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

  def add_additional_charges_to_invoice(invoice, charge_ids, custom_amounts)
    charge_ids.reject(&:blank?).each do |charge_id|
      charge = AdditionalChargePreset.find(charge_id)
      custom_amount = custom_amounts[charge_id]

      InvoiceItem.create_from_additional_charge(charge, invoice, custom_amount)
    end
  end

  def build_invoice_summary(release_notes, additional_charge_ids)
    "Invoice created successfully. Go to dashboard to push to Xero."
  end

  # Load additional charge presets for forms
  def load_additional_charges
    @additional_charge_presets = AdditionalChargePreset.enabled.ordered
  end

  def set_works_order
    @works_order = WorksOrder.find(params[:id])
  end

  # UPDATED: Removed part detail fields since they're handled by model callback
  def works_order_params
    # Always allow these core parameters
    permitted_params = [
      :customer_order_id, :part_id, :quantity, :price_type,
      :customer_reference
    ]

    # Add additional charges parameters
    permitted_params += [
      { selected_charge_ids: [] },
      { custom_amounts: {} }
    ]

    # Only permit the relevant price field based on price_type
    price_type = params[:works_order][:price_type]

    case price_type
    when 'each'
      permitted_params << :each_price
    when 'lot'
      permitted_params << :lot_price
    else
      # Default case - allow both for backward compatibility
      permitted_params += [:each_price, :lot_price]
    end

    filtered_params = params.require(:works_order).permit(*permitted_params)
    filtered_params
  end

  def load_reference_data
    @additional_charge_presets = AdditionalChargePreset.enabled.ordered

    if @customer_order.present?
      @parts = Part.enabled
                  .for_customer(@customer_order.customer)
                  .includes(:customer)
                  .order(:part_number)

      # Force query execution and count from database
      db_count = Part.enabled.for_customer(@customer_order.customer).count
    else
      @parts = Part.enabled
                  .includes(:customer)
                  .order(:part_number)
    end
  end

  def load_form_data_for_errors
    if params[:customer_order_id].present?
      @customer_order = CustomerOrder.find(params[:customer_order_id])
      @customer_orders = [@customer_order]
    elsif @works_order&.customer_order.present?
      @customer_order = @works_order.customer_order
      @customer_orders = [@customer_order]
    else
      @customer_order = nil
      @customer_orders = CustomerOrder.active.includes(:customer).order(created_at: :desc)
    end

    # Safety fallback - ensure @customer_orders is never nil
    @customer_orders ||= []

    load_reference_data
  end

  # SIMPLIFIED: Just validate part configuration, don't manually set part details
  def validate_part_configuration(works_order)
    return false unless works_order.customer_order && works_order.part_id.present?

    begin
      # Get the selected part
      part = Part.find(works_order.part_id)

      # Check if part has processing instructions configured
      if part.customisation_data.blank? || part.customisation_data.dig("operation_selection", "treatments").blank?
        works_order.errors.add(:part_id, "Part #{part.display_name} does not have processing instructions configured. Please set up this part properly first.")
        return false
      end

      return true
    rescue => e
      works_order.errors.add(:base, "Error validating part: #{e.message}")
      return false
    end
  end

  # ============================================================================
  # ROLE-BASED ACCESS CONTROL METHODS
  # ============================================================================

  def require_ecard_access
    unless Current.user&.sees_ecards?
      Rails.logger.warn "Unauthorized e-card access attempt by #{Current.user&.email_address || 'unknown user'}"
      redirect_to root_path, alert: "You don't have permission to access e-cards."
    end
  end
end
