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


  # ---------------------------------------------------------------------------
  # Quick bookout — release everything the process records currently certify,
  # for the whole order, in one go.
  #
  # A works order is auto-bookable only when HAMS itself can vouch for the
  # quantity: a paperless process record whose thickness (if required) is
  # captured in-line. Everything else is listed with a reason and released
  # manually through the normal form:
  #   :paper_record      — sign-offs live on the paper route card; HAMS can't
  #                        verify them, and (for measurable parts) thickness
  #                        readings have to be typed in anyway.
  #   :manual_thickness  — paperless record, but thickness is form-captured
  #                        (WO frozen before the in-line field existed).
  #   :awaiting_sign_off — paperless + in-line, but the certified through-line
  #                        is already fully released; nothing new signed off.
  #
  # Certified headroom is tracked PER PROCESS RECORD OWNER, not per works
  # order: a grouped bar's record certifies the whole tank load, so booking
  # several members of one group must share the same width. Candidates are
  # walked in WO-number order and each allocation is deducted before the next
  # member is sized, so the numbers shown in the modal are exactly what
  # quick_bookout! will create (validate_process_record_coverage remains the
  # backstop at save time).
  # ---------------------------------------------------------------------------
  BookoutCandidate = Struct.new(:works_order, :quantity, :reason, keyword_init: true)

  def bookout_candidates
    headroom = {} # process record owner id => certified width not yet released/allocated

    works_orders.active.where(is_open: true).order(:number).filter_map do |wo|
      next nil if wo.quantity_remaining <= 0

      unless wo.paperless_record?
        next BookoutCandidate.new(works_order: wo, quantity: 0, reason: :paper_record)
      end

      # Ask an unsaved RN, so the answer uses exactly the rules create will.
      probe = wo.release_notes.build
      if probe.requires_thickness_measurements? && !wo.inline_thickness_record?
        next BookoutCandidate.new(works_order: wo, quantity: 0, reason: :manual_thickness)
      end

      owner_id = wo.process_record_owner.id
      headroom[owner_id] ||= wo.signed_off_quantity - wo.released_quantity_against_record
      qty = [wo.quantity_remaining, headroom[owner_id]].min

      if qty <= 0
        BookoutCandidate.new(works_order: wo, quantity: 0, reason: :awaiting_sign_off)
      else
        headroom[owner_id] -= qty
        BookoutCandidate.new(works_order: wo, quantity: qty, reason: nil)
      end
    end
  end

  # Create one release note per selected bookable works order, everything as
  # accepted (rejections go through the manual form — they need remarks and
  # usually an NCR anyway). Quantities are recomputed server-side from
  # bookout_candidates, never taken from the client. All-or-nothing: any
  # validation failure rolls the whole bookout back.
  #
  # Returns [created_release_notes, skipped_display_names] — skipped covers
  # ids that were requested but are no longer bookable (someone released or
  # signed off in between).
  def quick_bookout!(works_order_ids, user)
    # UUID primary keys — compare as strings. (map(&:to_i) here previously
    # truncated "4461ba80-…" to 4461, so no posted id ever matched a
    # candidate and every bookout reported "no longer bookable".)
    ids     = Array(works_order_ids).map(&:to_s).reject(&:blank?)
    created = []
    skipped = []

    transaction do
      candidates = bookout_candidates
      requested  = candidates.select { |c| ids.include?(c.works_order.id.to_s) }
      bookable   = requested.select { |c| c.reason.nil? && c.quantity.positive? }
      skipped    = (requested - bookable).map { |c| c.works_order.display_name }
      # Ids posted but not among current candidates (voided/closed/released
      # since the page loaded). Truncate — a full UUID makes an ugly label.
      skipped   += (ids - requested.map { |c| c.works_order.id.to_s })
                     .map { |id| "WO##{id[0, 8]}…" }

      bookable.each do |c|
        created << c.works_order.release_notes.create!(
          date: Date.current,
          issued_by: user,
          quantity_accepted: c.quantity,
          quantity_rejected: 0
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
