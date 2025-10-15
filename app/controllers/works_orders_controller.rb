# app/controllers/works_orders_controller.rb - Fixed pricing parameter handling and route card operations with RBAC
class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :ecard, :sign_off_operation, :save_batches, :create_invoice, :void, :unvoid]
  before_action :require_ecard_access, only: [:ecard, :sign_off_operation, :save_batches, :save_operation_input]

 def index
    @works_orders = WorksOrder.includes(:customer_order, :part, :release_level, :transport_method, customer: [])

    # Apply user-specific e-card filtering if user sees e-cards
    if Current.user.sees_ecards?
      @works_orders = apply_ecard_filtering(@works_orders)
    end

    # Search functionality - supports multiple search types
    if params[:search].present?
      search_term = params[:search].strip

      # Handle RN/WO prefixes - if user types "RN1" or "WO22", extract the exact number
      if search_term.match(/^RN(\d+)$/i)
        # Exact release note number search
        release_note_number = search_term.match(/^RN(\d+)$/i)[1]
        @works_orders = @works_orders.where(
          "EXISTS(SELECT 1 FROM release_notes WHERE release_notes.works_order_id = works_orders.id AND release_notes.number = ?)",
          release_note_number.to_i
        )
      elsif search_term.match(/^WO(\d+)$/i)
        # Exact works order number search
        works_order_number = search_term.match(/^WO(\d+)$/i)[1]
        @works_orders = @works_orders.where("works_orders.number = ?", works_order_number.to_i)
      else
        # General search across all field
        @works_orders = @works_orders.joins(customer_order: :customer)
                                    .where(
                                      "CAST(works_orders.number AS TEXT) ILIKE ? OR " \
                                      "works_orders.part_number ILIKE ? OR " \
                                      "organizations.name ILIKE ? OR " \
                                      "EXISTS(SELECT 1 FROM release_notes WHERE release_notes.works_order_id = works_orders.id AND CAST(release_notes.number AS TEXT) ILIKE ?)",
                                      "%#{search_term}%", "%#{search_term}%", "%#{search_term}%", "%#{search_term}%"
                                    )
      end

      @works_orders = @works_orders.distinct
    elsif params[:customer_search].present?
      # Legacy customer search (for backwards compatibility)
      customer_search_term = params[:customer_search].strip
      @works_orders = @works_orders.joins(customer_order: :customer)
                                  .where("organizations.name ILIKE ?", "%#{customer_search_term}%")
    elsif params[:customer_id].present?
      @works_orders = @works_orders.for_customer(params[:customer_id])
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
      Rails.logger.error "Failed to create invoice: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"

      redirect_to @works_order,
                  alert: "❌ Failed to stage invoice: #{e.message}. Please try again or contact support."
    end
  end

  def ecard
    # Check user access (already handled by before_action, but add extra logging)
    unless Current.user.sees_ecards?
      Rails.logger.warn "Unauthorized e-card access attempt by #{Current.user.email_address}"
      redirect_to @works_order, alert: "You don't have permission to access e-cards."
      return
    end

    # Check if this specific work order matches user's filter criteria
    unless user_can_see_work_order?(@works_order)
      redirect_to works_orders_path, alert: "This work order is outside your assigned work area."
      return
    end

    # Original demo customer restriction can be removed or kept as additional filter
    demo_customers = ["24 Locks"]
    unless demo_customers.include?(@works_order.customer.name)
      redirect_to @works_order, alert: "E-Cards are currently in beta testing for select customers."
      return
    end
  end

  def save_batches
    # Permission check handled by before_action
    unless user_can_see_work_order?(@works_order)
      render json: { success: false, error: "This work order is outside your assigned work area." }
      return
    end

    batches_data = params[:batches] || []

    # Validate batch data
    unless batches_data.is_a?(Array)
      render json: { success: false, error: "Invalid batch data format" }
      return
    end

    # Initialize customised_process_data if blank
    @works_order.customised_process_data ||= {}

    # Store batches data
    @works_order.customised_process_data["batches"] = batches_data.map do |batch|
      {
        "id" => batch["id"],
        "number" => batch["number"].to_i,
        "quantity" => batch["quantity"].to_i,
        "status" => batch["status"],
        "createdAt" => batch["createdAt"],
        "currentOperation" => batch["currentOperation"].to_i
      }
    end

    if @works_order.save
      render json: {
        success: true,
        message: "Batches saved successfully",
        batches: @works_order.customised_process_data["batches"]
      }
    else
      render json: {
        success: false,
        error: "Failed to save batches: #{@works_order.errors.full_messages.join(', ')}"
      }
    end
  end

  def save_operation_input
    # Permission check handled by before_action
    unless user_can_see_work_order?(@works_order)
      render json: { success: false, error: "This work order is outside your assigned work area." }
      return
    end

    operation_position = params[:operation_position].to_s
    input_index = params[:input_index].to_s
    value = params[:value].to_s

    # Initialize customised_process_data structure if needed
    @works_order.customised_process_data ||= {}
    @works_order.customised_process_data["operation_inputs"] ||= {}
    @works_order.customised_process_data["operation_inputs"][operation_position] ||= {}

    # Save the input value
    @works_order.customised_process_data["operation_inputs"][operation_position][input_index] = value

    if @works_order.save
      render json: { success: true }
    else
      render json: { success: false, error: "Failed to save input" }
    end
  end

  def sign_off_operation
    # Permission check handled by before_action
    unless user_can_see_work_order?(@works_order)
      redirect_to @works_order, alert: "This work order is outside your assigned work area."
      return
    end

    position = params[:operation_position].to_i
    batch_id = params[:batch_id]

    # Initialize customised_process_data if blank
    @works_order.customised_process_data ||= {}

    if batch_id == "independent"
      # Batch-independent operation (Contract Review, Final Inspection, Pack)
      @works_order.customised_process_data["operations"] ||= {}
      @works_order.customised_process_data["operations"][position.to_s] = {
        "signed_off_by" => Current.user.id,
        "signed_off_at" => Time.current.iso8601
      }
    else
      # Batch-dependent operation
      @works_order.customised_process_data["batch_operations"] ||= {}
      @works_order.customised_process_data["batch_operations"][batch_id] ||= {}
      @works_order.customised_process_data["batch_operations"][batch_id][position.to_s] = {
        "signed_off_by" => Current.user.id,
        "signed_off_at" => Time.current.iso8601,
        "batch_id" => batch_id
      }
    end

    if @works_order.save
      redirect_to ecard_works_order_path(@works_order), notice: "Operation signed off"
    else
      redirect_to ecard_works_order_path(@works_order), alert: "Failed to sign off"
    end
  end

  private

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
      :release_level_id, :transport_method_id, :customer_reference
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
    @release_levels = ReleaseLevel.enabled.ordered
    @transport_methods = TransportMethod.enabled.ordered
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

  # Check if current user can see a specific work order based on their filter criteria
  def user_can_see_work_order?(work_order)
    return true unless Current.user.sees_ecards? # If they can't see e-cards, don't filter

    filter_criteria = Current.user.ecard_filter_criteria
    return true if filter_criteria.blank? # No filtering = see everything

    part = work_order.part
    return true unless part # If no part, allow access

    operations = part.get_operations_with_auto_ops
    customisation_data = part.customisation_data || {}

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

  # Apply user-specific filtering to the works orders collection
  def apply_ecard_filtering(works_orders)
    return works_orders unless Current.user.sees_ecards?

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
end
