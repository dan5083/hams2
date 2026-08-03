# app/controllers/works_orders_controller.rb - Fixed pricing parameter handling and route card operations with RBAC
class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :invoice_to_date, :void, :unvoid, :sign_off_operation, :save_ocv, :set_batch_count, :set_parts_per_batch, :set_batch_qty, :discard_process_record]

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

    # For route card visibility — one query for the page, not one per row
    part_ids = @works_orders.map(&:part_id).compact
    @part_wo_counts = WorksOrder.where(part_id: part_ids).group(:part_id).count
  end

  # The process record is scoped to ONE batch at a time. Rendering every batch
  # of every operation is what made 20 a practical ceiling; with the page
  # pinned to a single batch the cost no longer scales with batch count.
  def show
    return unless @works_order.paperless_record?

    requested = params[:batch].to_i
    valid = (1..@works_order.process_batch_count).cover?(requested)
    @active_batch = valid ? requested : @works_order.first_incomplete_batch
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
        all_variables: [],
        ocv: operation.try(:ocv)
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

  # Invoice everything released TO DATE on THIS works order only (partial is
  # fine). Drives off requires_invoicing release notes via Invoice.stage_to_date,
  # which bills courier per release note and is safe to call repeatedly.
  # Triggered by the 🐤 button on the dashboard "Released but Uninvoiced"
  # worklist.
  def invoice_to_date
    release_notes = ReleaseNote.joins(:works_order)
                               .where(works_orders: { id: @works_order.id })
                               .requires_invoicing

    invoice = Invoice.stage_to_date(release_notes, Current.user)

    if invoice
      redirect_to root_path,
                  notice: "✅ Invoice INV#{invoice.number} staged for WO#{@works_order.number} (released to date). Push to Xero from the dashboard."
    else
      redirect_to root_path,
                  alert: "Nothing to invoice on WO#{@works_order.number} — it may already be invoiced to date."
    end
  rescue StandardError => e
    Rails.logger.error "invoice_to_date (WO #{@works_order.id}) failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to root_path, alert: "❌ Failed to stage invoice: #{e.message}"
  end

  # Paperless process record: operator sign-off per operation per batch
  def sign_off_operation
    return redirect_to(works_order_path(@works_order), alert: "This works order's process record is on paper.") unless @works_order.paperless_record?
    @works_order.sign_off_operation!(params[:position], params[:batch], Current.user)
    redirect_to process_record_path(params[:position], advance_from: params[:batch]),
                notice: "Operation #{params[:position]} batch #{params[:batch]} signed off."
  rescue => e
    redirect_to process_record_path(params[:position]), alert: e.message
  end

  # Paperless process record: OCV readings for the ACTIVE batch of an operation
  def save_ocv
    return redirect_to(works_order_path(@works_order), alert: "This works order's process record is on paper.") unless @works_order.paperless_record?
    readings = params.fetch(:readings, {}).permit!.to_h
    @works_order.save_ocv_readings!(params[:position], readings, Current.user) if readings.present?
    checklist = params.fetch(:checklist, {}).permit!.to_h
    @works_order.save_checklist_responses!(params[:position], checklist, Current.user) if checklist.present?
    if params[:sign_off_batch].present?
      @works_order.sign_off_operation!(params[:position], params[:sign_off_batch], Current.user)
      notice = "Readings saved; operation #{params[:position]} batch #{params[:sign_off_batch]} signed off."
      target = process_record_path(params[:position], advance_from: params[:sign_off_batch])
    else
      notice = "OCV readings saved for operation #{params[:position]}."
      target = process_record_path(params[:position])
    end
    redirect_to target, notice: notice
  rescue => e
    redirect_to process_record_path(params[:position]), alert: e.message
  end

  # Bin the frozen process record and go back to rendering live from the part.
  # Gated on no release notes - the same test that gates voiding.
  def discard_process_record
    @works_order.discard_process_record!(Current.user, params[:reason])
    redirect_to works_order_path(@works_order),
                notice: "Process record discarded. Operations now render live from the part - check them before signing anything."
  rescue => e
    redirect_to works_order_path(@works_order), alert: e.message
  end

  # Paperless process record: the normal way to batch a WO - state the load
  # size and let the count and the remainder batch fall out.
  def set_parts_per_batch
    return redirect_to(works_order_path(@works_order), alert: "This works order's process record is on paper.") unless @works_order.paperless_record?
    @works_order.set_parts_per_batch!(params[:parts_per_batch])
    count = @works_order.process_batch_count
    redirect_to works_order_path(@works_order),
                notice: "Batched at #{params[:parts_per_batch]} per batch: #{count} batch#{'es' unless count == 1}."
  rescue => e
    redirect_to works_order_path(@works_order), alert: e.message
  end

  # Paperless process record: correct a single batch's quantity (short load,
  # scrapped part) without re-deriving the whole structure.
  def set_batch_qty
    return redirect_to(works_order_path(@works_order), alert: "This works order's process record is on paper.") unless @works_order.paperless_record?
    @works_order.set_batch_qty!(params[:batch], params[:qty])
    redirect_to works_order_path(@works_order, batch: params[:batch]),
                notice: "Batch #{params[:batch]} quantity updated."
  rescue => e
    redirect_to works_order_path(@works_order, batch: params[:batch]), alert: e.message
  end

  # Paperless process record: how many batches this WO runs. Manual escape
  # hatch; set_parts_per_batch is the everyday path.
  def set_batch_count
    return redirect_to(works_order_path(@works_order), alert: "This works order's process record is on paper.") unless @works_order.paperless_record?
    @works_order.set_batch_count!(params[:batch_count], params.fetch(:batch_qtys, {}).permit!.to_h)
    redirect_to works_order_path(@works_order), notice: "Batch count set to #{params[:batch_count]}."
  rescue => e
    redirect_to works_order_path(@works_order), alert: e.message
  end

  private

  # Where to land after acting on an operation. Without advance_from the active
  # batch and operation are held. With it, the page walks down the operations of
  # the batch just signed - an operator takes a batch through its route in one
  # rhythm - and only when that batch is finished does it drop onto the first
  # outstanding operation of the next incomplete batch.
  def process_record_path(position, advance_from: nil)
    batch = params[:batch].presence || params[:sign_off_batch].presence
    anchor_position = position

    if advance_from.present?
      batch = advance_from

      if (nxt_op = @works_order.next_unsigned_operation_in(advance_from, after: position))
        anchor_position = nxt_op
      else
        statuses = @works_order.batch_statuses
        nxt_batch = statuses.find { |n, s| n > advance_from.to_i && s != :complete }&.first ||
                    statuses.find { |_n, s| s != :complete }&.first

        if nxt_batch && nxt_batch.to_i != advance_from.to_i
          batch = nxt_batch
          anchor_position = @works_order.next_unsigned_operation_in(nxt_batch) || position
        end
      end
    end

    works_order_path(@works_order, batch: batch, anchor: "op-#{anchor_position}")
  end

  def create_bulk
    works_orders_params = params[:works_orders]
    results = []
    created_works_orders = []

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
          created_works_orders << wo
        else
          results << { part_id: wo_params[:part_id], status: 'error', errors: wo.errors.full_messages }
        end
      end
    end

    # Send one order acknowledgement email per customer order covered by this batch.
    # Sent inline (deliver_now): the production queue adapter is :async (in-process,
    # non-durable), so deliver_later jobs can be lost on dyno restart/deploy. The
    # rescue keeps a mail failure from failing the order-creation request.
    # Recipients come from Organization#buyer_emails: enabled buyers if configured,
    # otherwise the Xero primary contact email.
    created_works_orders.group_by(&:customer_order).each do |customer_order, wos|
      next unless customer_order && customer_order.customer.buyer_emails.any?

      begin
        OrderAcknowledgementMailer.order_confirmation(customer_order, wos).deliver_now
        Rails.logger.info "Order acknowledgement email sent for #{customer_order.customer.name} (Order #{customer_order.number}) to #{customer_order.customer.buyer_emails.join(', ')}"
      rescue => e
        Rails.logger.error "Failed to send order acknowledgement email for Order #{customer_order.number}: #{e.message}"
        Rails.logger.error e.backtrace.first(3).join("\n")
      end
    end

    customer_order_id = works_orders_params.first[:customer_order_id]
    render json: {
      results: results,
      redirect_url: customer_order_path(customer_order_id)
    }
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
end
