# app/controllers/works_orders_controller.rb - Fixed pricing parameter handling and route card operations
class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :create_invoice]


 def index
    @works_orders = WorksOrder.includes(:customer_order, :part, :release_level, :transport_method, customer: [])
                              .active

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
        # General search across all fields
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

  # UPDATED: Smart parameter filtering based on price_type and additional charges
  def works_order_params
    # Always allow these core parameters
    permitted_params = [
      :customer_order_id, :part_id, :quantity, :price_type,
      :part_number, :part_issue, :part_description,
      :release_level_id, :transport_method_id
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
      # Default case - allow both for backward compatibility, but log warning
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
      works_order.part_number = part.part_number
      works_order.part_issue = part.part_issue
      works_order.part_description = part.description || "#{part.part_number} component"

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
