# app/models/customer_order.rb - Fixed outstanding logic and auto-marking
class CustomerOrder < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  has_many :works_orders, dependent: :restrict_with_error
  has_many :release_notes, through: :works_orders

  validates :number, presence: true
  validates :number, uniqueness: { scope: :customer_id }
  validates :date_received, presence: true

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(date_received: :desc) }

  # FIXED: Outstanding logic - check for open works orders, not just any works orders
  scope :outstanding, -> {
    where(voided: false).where(
      'NOT EXISTS (SELECT 1 FROM works_orders WHERE works_orders.customer_order_id = customer_orders.id) OR ' +
      'EXISTS (SELECT 1 FROM works_orders WHERE works_orders.customer_order_id = customer_orders.id AND works_orders.voided = false AND works_orders.is_open = true)'
    )
  }

  after_initialize :set_defaults, if: :new_record?
  after_create :mark_customer_as_customer

  # Audit stamping. Current.user is set per-request by the auth layer; the
  # guard means console/rake saves keep the last real web user rather than
  # nulling the stamp out.
  before_create -> { self.created_by ||= Current.user }
  before_save   -> { self.updated_by = Current.user if Current.user }

  def display_name
    "#{customer.name} - #{number}"
  end

  def invoice_customer_name
    customer.name
  end

  def invoice_address
    customer.contact_address
  end

  def delivery_customer_name
    customer.name
  end

  def delivery_address
    customer.contact_address
  end

  def void!
    transaction do
      if has_non_voided_works_orders?
        raise StandardError, "Cannot void customer order until every works order has been voided"
      end
      update!(voided: true)
    end
  end

  def can_be_voided?
    !has_non_voided_works_orders?
  end

  def has_non_voided_works_orders?
    works_orders.active.exists?
  end

  def total_value
    works_orders.active.sum(:lot_price)
  end

  def total_quantity
    works_orders.active.sum(:quantity)
  end

  # ---------------------------------------------------------------------------
  # Delivery / advice note consolidation
  #
  # A collection for an order can cover several release notes. Instead of making
  # the driver sign one advice note per release note, the advice note is printed
  # only on the "lead" release note (the lowest-numbered active one for the
  # order), and that single advice note summarises every release note on the
  # order. See app/views/release_notes/pdf.html.erb.
  # ---------------------------------------------------------------------------

  # Active (non-voided) release notes for this order, lowest number first.
  # Eager-loads works_order to avoid N+1 when building the advice-note summary.
  def delivery_release_notes
    release_notes.active.includes(:works_order).order(:number)
  end

  # The release note that carries the consolidated advice note.
  def lead_release_note
    delivery_release_notes.first
  end

  # ---------------------------------------------------------------------------
  # Order-complete notification (CustomerOrderMailer#order_ready)
  # ---------------------------------------------------------------------------

  # Every active works order fully released, and there's at least one.
  # Queried fresh (not from counter caches) so the trigger in
  # WorksOrder#update_is_fully_released_flag can't race the cache update.
  def fully_released?
    return false if voided?
    active_wos = works_orders.active
    active_wos.exists? && !active_wos.where(is_fully_released: false).exists?
  end

  # Does any active works order on this order carry a carriage/courier charge?
  # Decides "ready to collect" vs "dispatching by courier" in the
  # order-complete email. Non-carriage extras (rework etc.) don't count —
  # see AdditionalChargePreset#carriage?.
  def carriage_charge_present?
    charge_ids = works_orders.active
                             .flat_map { |wo| Array(wo.selected_charge_ids) }
                             .uniq
    return false if charge_ids.empty?

    AdditionalChargePreset.where(id: charge_ids).any?(&:carriage?)
  end

  # Release notes whose CofC PDFs get attached to the order-complete email:
  # active notes on active works orders (voided WOs can't have release notes
  # anyway — can_be_voided? requires none — but belt and braces).
  def email_release_notes
    release_notes.active
                 .joins(:works_order)
                 .where(works_orders: { voided: false })
                 .includes(works_order: :customer_order)
                 .order(:number)
  end

  # FIXED: Outstanding logic - should check for open works orders
  def outstanding?
    return false if voided?
    works_orders.empty? || works_orders.where(voided: false, is_open: true).exists?
  end

  def can_be_deleted?
    works_orders.empty?
  end

  # ---------------------------------------------------------------------------
  # Customer PO attachment (Cloudinary) — see PurchaseOrderService.
  # po_document is a jsonb hash: public_id, secure_url, format, bytes,
  # source ("pdf" / "scanned_images" / "upload"), attached_at.
  # ---------------------------------------------------------------------------
  def po_attached?
    po_document.present?
  end

  def po_document_url
    po_document&.dig("secure_url")
  end

  # Cloudinary first-page thumbnail of the PO PDF, for the order page card.
  # Same shape as the drawing thumbnails on the works order page — if
  # Part#file_thumbnail_url uses a different transformation string, mirror
  # it here so the two look alike.
  def po_thumbnail_url
    url = po_document_url
    return unless url&.include?("/upload/")
    url.sub("/upload/", "/upload/pg_1,w_224,h_288,c_fill,g_north,f_jpg,q_auto/").sub(/\.\w+\z/, ".jpg")
  end

  # Same document with a Content-Disposition: attachment flag.
  def po_download_url
    po_document_url&.sub("/upload/", "/upload/fl_attachment/")
  end


  # ---------------------------------------------------------------------------
  # Bulk release ("bookout") — the release note form for a whole order:
  # one row per works order, prefilled with everything the process record
  # certifies but hasn't released, editable down (rejections, short
  # releases), never up. See customer_orders/bookout.html.erb.
  #
  # A works order is bookable when HAMS itself can vouch for the quantity: a
  # process record (its own, or the group lead's) whose thickness, if
  # required, is captured in-line. Everything else is listed with a reason:
  #   :no_record         — the record owner has no open paperless record
  #                        (record closed, or a part not yet paperless).
  #   :manual_thickness  — thickness is form-captured (WO frozen before the
  #                        in-line field existed); release via the WO form.
  #   :awaiting_sign_off — the certified through-line is already fully
  #                        released; nothing new signed off.
  #
  # Headroom comes from WorksOrder#certified_unreleased_quantity:
  #   * split record  — the lead's batches say how many of THIS WO's parts
  #                     went through, so the figure is per works order and
  #                     members don't compete for it.
  #   * unsplit/solo  — the record certifies the bar as one number; members
  #                     share it. Candidates are walked in WO-number order and
  #                     each allocation is deducted before the next member is
  #                     sized, so the modal shows exactly what quick_bookout!
  #                     will create (validate_process_record_coverage remains
  #                     the backstop at save time). This is a guess at who
  #                     gets what — split the batches on the lead to avoid it.
  # ---------------------------------------------------------------------------
  BookoutCandidate = Struct.new(:works_order, :quantity, :reason, :pooled, keyword_init: true)

  # Works orders the record certifies parts for that nobody has released:
  # the gap a Proof of Collection printed right now would paper over. The
  # collection pack and the lead RN's PoC refuse to print while this is
  # non-empty (see CustomerOrdersController#collection_pack).
  def releasable_candidates
    return [] if voided?
    bookout_candidates.select { |c| c.reason.nil? && c.quantity.positive? }
  end

  def bookout_candidates
    pooled = {} # record owner id => unsplit certified width not yet released/allocated

    works_orders.active.where(is_open: true).order(:number).filter_map do |wo|
      next nil if wo.quantity_remaining <= 0

      # Resolve through the owner: a grouped member's own paperless_record?
      # is false by design (its page renders no record UI), but its parts
      # are certified by the lead's record all the same.
      unless wo.process_record_owner.paperless_record?
        next BookoutCandidate.new(works_order: wo, quantity: 0, reason: :no_record)
      end

      # Ask an unsaved RN, so the answer uses exactly the rules create will.
      probe = wo.release_notes.build
      if probe.requires_thickness_measurements? && !wo.inline_thickness_record?
        next BookoutCandidate.new(works_order: wo, quantity: 0, reason: :manual_thickness)
      end

      if wo.split_record?
        available = wo.certified_unreleased_quantity
        is_pooled = false
      else
        owner_id = wo.process_record_owner.id
        pooled[owner_id] ||= wo.certified_unreleased_quantity
        available = pooled[owner_id]
        is_pooled = wo.grouped?
      end
      qty = [wo.quantity_remaining, available].min

      if qty <= 0
        BookoutCandidate.new(works_order: wo, quantity: 0, reason: :awaiting_sign_off, pooled: is_pooled)
      else
        pooled[owner_id] -= qty unless wo.split_record?
        BookoutCandidate.new(works_order: wo, quantity: qty, reason: nil, pooled: is_pooled)
      end
    end
  end

  # Bulk release: one release note per works order in `rows`, with the
  # operator's accepted / rejected quantities and (optional) statement.
  #
  #   rows: { works_order_id => { "accepted" => "48", "rejected" => "2", "remarks" => "" } }
  #
  # The quantities are the operator's, but they are checked against
  # bookout_candidates recomputed NOW: a row may release at most what the
  # process record certifies for that works order (its own share on a split
  # record, its allocation of the pooled width otherwise), so the record
  # stays the ceiling even though the form is editable. Rows totalling zero
  # are ignored. All-or-nothing: any over-release or validation failure
  # rolls the whole bookout back.
  #
  # Returns [created_release_notes, skipped_display_names] — skipped covers
  # ids that were posted but are no longer bookable (someone released,
  # signed off or voided in between) or that asked for more than is
  # certified.
  def quick_bookout!(rows, user)
    rows    = (rows || {}).to_h.transform_keys(&:to_s)
    created = []
    skipped = []

    transaction do
      candidates = bookout_candidates.index_by { |c| c.works_order.id.to_s }

      rows.each do |wo_id, attrs|
        attrs    = (attrs || {}).to_h.transform_keys(&:to_s)
        accepted = attrs["accepted"].to_i
        rejected = attrs["rejected"].to_i
        next if accepted <= 0 && rejected <= 0
        raise "Quantities cannot be negative" if accepted < 0 || rejected < 0

        c = candidates[wo_id]
        if c.nil?
          # Voided/closed/fully released since the page loaded. Truncate —
          # a full UUID makes an ugly label.
          skipped << "WO##{wo_id[0, 8]}…"
          next
        end
        if c.reason || c.quantity <= 0
          skipped << c.works_order.display_name
          next
        end
        if accepted + rejected > c.quantity
          raise "#{c.works_order.display_name}: asked to release #{accepted + rejected} but the process " \
                "record only certifies #{c.quantity} unreleased part(s)#{c.pooled ? ' (pooled across the group)' : ''}"
        end

        created << c.works_order.release_notes.create!(
          date: Date.current,
          issued_by: user,
          quantity_accepted: accepted,
          quantity_rejected: rejected,
          remarks: attrs["remarks"].presence # nil => standard CofC statement
        )
      end
    end

    [created, skipped]
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.date_received = Date.current if date_received.blank?
  end

  def mark_customer_as_customer
    unless customer.is_customer?
      customer.update!(is_customer: true)
      Rails.logger.info "Auto-marked #{customer.name} as customer due to new customer order #{number}"
    end
  end
end
