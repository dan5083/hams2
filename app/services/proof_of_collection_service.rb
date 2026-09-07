# app/services/proof_of_collection_service.rb
#
# Single entry point for the AI assistant: a photographed, signed Proof of
# Collection comes in → invoice whatever on that customer order has been
# released but not invoiced → push to Xero (SUBMITTED = Awaiting Approval) →
# attach the PoC as a PDF on the Xero invoice. Nothing is stored locally; the
# Xero invoice is the PoC's home.
#
# One call, deliberately: each step depends on the previous one's result
# (invoice → Xero id → attachment target), and the base64 file data only
# exists during this assistant run.
#
# Usage from AI assistant:
#   ProofOfCollectionService.process_from_request(
#     customer_order_id: co.id,
#     request_id: @request_id
#   )
#
# Idempotency: release notes leave `requires_invoicing` once invoiced, so a
# second photo of the same PoC finds nothing new to stage, reuses the latest
# invoice covering the order, skips the push if it already has a xero_id, and
# (re)attaches the PoC. A partial failure (e.g. Xero down after staging)
# leaves the invoice in HAMS unsynced; running again pushes it.
class ProofOfCollectionService
  class Error < StandardError; end

  def self.process_from_request(customer_order_id:, request_id:, include_online: false)
    co = CustomerOrder.includes(:customer).find(customer_order_id)

    # ── 1. Stage (or find) the invoice ────────────────────────────────────
    rns = ReleaseNote.requires_invoicing
                     .joins(works_order: :customer_order)
                     .where(customer_orders: { id: co.id })
                     .includes(:works_order)
                     .to_a

    # Snapshot before staging — once invoiced they leave the scope.
    staged_rns = rns.map { |rn| { number: rn.number, works_order: rn.works_order.number, qty: rn.quantity_accepted } }

    invoice =
      if rns.any?
        Invoice.stage_to_date(rns) or raise Error, "Invoice failed to stage"
      else
        existing_invoice_for(co) or
          raise Error, "Nothing left to invoice on customer order #{co.number} and no existing invoice found for it."
      end
    staged = rns.any?

    # ── 2. Push to Xero if not already there ──────────────────────────────
    xero   = XeroInvoiceService.from_current_token
    pushed = false
    if invoice.requires_xero_sync?
      result = xero.push_invoice(invoice)
      raise Error, result[:message] unless result[:success]
      invoice.reload
      pushed = true
    end

    # ── 3. Build the PoC PDF and attach it to the Xero invoice ────────────
    doc = ScannedDocumentService.pdf_from_request(request_id: request_id)

    attach = xero.attach_file(
      invoice_id:     invoice.xero_id,
      file_bytes:     doc[:bytes],
      file_name:      "ProofOfCollection_#{co.number.to_s.parameterize}_#{invoice.display_name}.pdf",
      include_online: include_online
    )
    raise Error, "Invoice #{invoice.display_name} is in Xero but the PoC failed to attach: #{attach[:error]}" unless attach[:success]

    {
      success:        true,
      customer_order: co.number,
      invoice_id:     invoice.id,
      invoice_number: invoice.display_name,
      xero_url:       invoice.xero_url,
      total_ex_tax:   invoice.total_ex_tax.to_f,
      staged_new:     staged,
      pushed_to_xero: pushed,
      release_notes:  staged_rns,
      poc_pages:      doc[:pages],
      poc_attached:   true
    }
  rescue => e
    Rails.logger.error "[ProofOfCollectionService] #{e.class}: #{e.message}"
    { success: false, error: e.message, invoice_number: invoice&.display_name, invoice_id: invoice&.id }.compact
  end

  # Most recent invoice that has a main line for any release note on this order.
  def self.existing_invoice_for(customer_order)
    Invoice.joins(invoice_items: { release_note: :works_order })
           .where(works_orders: { customer_order_id: customer_order.id })
           .order(created_at: :desc)
           .first
  end
  private_class_method :existing_invoice_for
end
