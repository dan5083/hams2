# app/controllers/works_orders_controller.rb - Simplified version
class WorksOrdersController < ApplicationController
 before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card, :complete, :create_invoice]

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
   @works_order = WorksOrder.new

   # If coming from nested route, pre-select the customer order
   if params[:customer_order_id].present?
     @customer_order = CustomerOrder.find(params[:customer_order_id])
     @works_order.customer_order = @customer_order
     @customer_orders = [@customer_order] # Only show the selected customer order
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

   # Set up the part and PPI automatically
   if setup_part_and_ppi(@works_order)
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
   # For updates, we might need to recreate the part/PPI if part details changed
   if part_details_changed?
     setup_part_and_ppi(@works_order)
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
   @operations = build_operations_from_process(@works_order)

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

 def complete
   if @works_order.can_be_completed?
     @works_order.complete!(Current.user)
     redirect_to @works_order, notice: 'Works order completed successfully.'
   else
     redirect_to @works_order, alert: 'Cannot complete works order - insufficient quantity released.'
   end
 end

 def create_invoice
    Rails.logger.info "🚀 CREATE_INVOICE: Starting for WO#{@works_order.number}"

    if @works_order.quantity_released <= 0
      Rails.logger.info "❌ CREATE_INVOICE: No quantity released (#{@works_order.quantity_released})"
      redirect_to @works_order, alert: 'No items available to invoice - no quantity has been released yet.'
      return
    end

    # Check Xero connection
    unless session[:xero_token_set] && session[:xero_tenant_id]
      Rails.logger.info "❌ CREATE_INVOICE: No Xero connection"
      redirect_to @works_order, alert: 'Please connect to Xero first before creating invoices.'
      return
    end

    begin
      # Get all uninvoiced release notes for this works order
      uninvoiced_release_notes = @works_order.release_notes.requires_invoicing
      Rails.logger.info "🔍 CREATE_INVOICE: Found #{uninvoiced_release_notes.count} uninvoiced release notes"

      uninvoiced_release_notes.each do |rn|
        Rails.logger.info "  - RN#{rn.number}: #{rn.quantity_accepted} accepted, can_be_invoiced=#{rn.can_be_invoiced?}"
      end

      if uninvoiced_release_notes.empty?
        Rails.logger.info "❌ CREATE_INVOICE: No uninvoiced release notes found"
        redirect_to @works_order, alert: 'No release notes available for invoicing.'
        return
      end

      # Create local invoice from release notes
      customer = @works_order.customer
      Rails.logger.info "🔍 CREATE_INVOICE: Customer: #{customer.name} (ID: #{customer.id})"
      Rails.logger.info "🔍 CREATE_INVOICE: Customer has Xero contact: #{customer.xero_contact&.xero_id.present?}"

      # Check if customer has Xero contact
      unless customer.xero_contact&.xero_id
        Rails.logger.info "❌ CREATE_INVOICE: Customer #{customer.name} has no Xero contact"
        redirect_to @works_order,
                    alert: "Customer #{customer.name} does not have a Xero contact. Please sync customers from Xero first."
        return
      end

      Rails.logger.info "🔍 CREATE_INVOICE: Calling Invoice.create_from_release_notes..."
      invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

      if invoice.nil?
        Rails.logger.error "❌ CREATE_INVOICE: Invoice.create_from_release_notes returned nil"

        # Let's check what went wrong by testing the conditions manually
        Rails.logger.info "🔍 DEBUG: Testing release notes conditions..."

        uninvoiced_release_notes.each_with_index do |rn, i|
          Rails.logger.info "  Release Note #{i+1}: can_be_invoiced? = #{rn.can_be_invoiced?}"
          Rails.logger.info "    - voided: #{rn.voided}"
          Rails.logger.info "    - quantity_accepted: #{rn.quantity_accepted}"
          Rails.logger.info "    - no_invoice: #{rn.no_invoice}"
          Rails.logger.info "    - invoice_item present: #{rn.invoice_item.present?}"
        end

        # Try to create an invoice manually to see validation errors
        Rails.logger.info "🔍 DEBUG: Testing invoice creation manually..."
        test_invoice = Invoice.new(customer: customer, date: Date.current)
        if test_invoice.valid?
          Rails.logger.info "✅ DEBUG: Test invoice is valid"
        else
          Rails.logger.error "❌ DEBUG: Test invoice validation errors: #{test_invoice.errors.full_messages}"
        end

        redirect_to @works_order, alert: 'Failed to create invoice from release notes. Check logs for details.'
        return
      end

      Rails.logger.info "✅ CREATE_INVOICE: Invoice INV#{invoice.number} created successfully"

      # Push to Xero using existing service
      Rails.logger.info "🔍 CREATE_INVOICE: Pushing to Xero..."
      xero_service = XeroInvoiceService.new(session[:xero_token_set], session[:xero_tenant_id])
      result = xero_service.push_invoice(invoice)

      if result[:success]
        Rails.logger.info "✅ CREATE_INVOICE: Xero push successful"
        redirect_to @works_order,
                    notice: "✅ #{result[:message]}! " \
                            "Invoiced #{uninvoiced_release_notes.count} release note(s) " \
                            "for #{uninvoiced_release_notes.sum(:quantity_accepted)} parts."
      else
        Rails.logger.error "❌ CREATE_INVOICE: Xero push failed: #{result[:error]}"
        redirect_to @works_order,
                    alert: "⚠️ Local invoice INV#{invoice.number} created, but failed to sync to Xero: #{result[:error]}. " \
                          "Please try syncing manually from the invoices page."
      end

    rescue StandardError => e
      Rails.logger.error "💥 CREATE_INVOICE: Exception occurred: #{e.message}"
      Rails.logger.error "💥 CREATE_INVOICE: Backtrace: #{e.backtrace.first(10).join("\n")}"

      redirect_to @works_order,
                  alert: "❌ Failed to create invoice: #{e.message}. Please try again or contact support."
    end
  end

 private

 def set_works_order
   @works_order = WorksOrder.find(params[:id])
 end

 def works_order_params
   params.require(:works_order).permit(
     :customer_order_id, :part_id, :quantity, :lot_price, :each_price, :price_type,
     :part_number, :part_issue, :part_description, :release_level_id, :transport_method_id
   )
 end

 def load_reference_data
   @release_levels = ReleaseLevel.enabled.ordered
   @transport_methods = TransportMethod.enabled.ordered

   # Load all parts for the customer (temporarily remove PPI requirement to debug)
   if @customer_order.present?
     @parts = Part.enabled
                  .for_customer(@customer_order.customer)
                  .includes(:customer, :part_processing_instructions)
                  .order(:uniform_part_number)

     Rails.logger.info "🔍 Loading parts for customer: #{@customer_order.customer.name}"
     Rails.logger.info "🔍 Found #{@parts.count} parts"
     @parts.each do |part|
       ppis = part.part_processing_instructions.where(customer: @customer_order.customer, enabled: true)
       Rails.logger.info "🔍 Part #{part.display_name}: #{ppis.count} PPIs"
     end
   else
     @parts = Part.enabled
                  .includes(:customer, :part_processing_instructions)
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

 def setup_part_and_ppi(works_order)
   return false unless works_order.customer_order && works_order.part_id.present?

   customer = works_order.customer_order.customer

   begin
     # Get the selected part
     part = Part.find(works_order.part_id)
     works_order.part = part
     works_order.part_number = part.uniform_part_number
     works_order.part_issue = part.uniform_part_issue
     works_order.part_description = part.description || "#{part.uniform_part_number} component"

     # Find THE PPI for this part and customer (should only be one)
     ppi = PartProcessingInstruction.find_by(
       part: part,
       customer: customer,
       enabled: true
     )

     if ppi.blank?
       works_order.errors.add(:part_id, "No processing instruction found for #{part.display_name}. Please set up this part properly first.")
       return false
     end

     # Use the PPI
     works_order.ppi = ppi

     return true
   rescue => e
     works_order.errors.add(:base, "Error setting up part: #{e.message}")
     return false
   end
 end

 def part_details_changed?
   @works_order.part_number_changed? || @works_order.part_issue_changed?
 end

 def build_operations_from_process(works_order)
   # Simple default operation for route cards
   [
     {
       number: 1,
       content: [
         {
           type: 'paragraph',
           as_html: works_order.ppi&.specification || "Process as per customer requirements"
         }
       ],
       all_variables: []
     }
   ]
 end
end
