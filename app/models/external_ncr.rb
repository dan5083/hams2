# app/models/external_ncr.rb
class ExternalNcr < ApplicationRecord
  # --- Associations ---
  has_many :external_ncr_release_notes, dependent: :destroy, inverse_of: :external_ncr
  has_many :release_notes, through: :external_ncr_release_notes

  belongs_to :created_by, class_name: 'User'
  belongs_to :respondent, class_name: 'User', foreign_key: 'assigned_to_id'

  # JSONB accessors for NCR-specific data
  store_accessor :ncr_data,
    # Identification numbers
    :concession_number,
    :customer_ncr_number,
    :estimated_cost,

    # Quantities
    :reject_quantity,

    # NCR Content (in workflow order)
    :description_of_non_conformance,
    :containment_action,
    :root_cause_analysis,
    :corrective_action,
    :preventive_action,
    :completed_by_user_id,

    # Cloudinary document storage
    :cloudinary_public_id,
    :cloudinary_url,
    :original_filename,
    :file_size_bytes,
    :content_type,
    :document_uploaded_at

  # --- Validations ---
  validates :hal_ncr_number, presence: true, uniqueness: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :created_by_id, presence: true
  validates :status, inclusion: { in: %w[draft in_progress completed] }
  validate :at_least_one_release_note

  # Validate quantities if provided
  validates :reject_quantity, numericality: { greater_than: 0 }, allow_blank: true
  validates :estimated_cost, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true

  # --- Scopes ---
  scope :active, -> { where.not(status: 'completed') }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_customer, ->(customer) {
    joins(release_notes: { works_order: :customer_order })
      .where(customer_orders: { customer_id: customer.id })
      .distinct
  }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_documents, -> { where.not(ncr_data: { cloudinary_public_id: [nil, ''] }) }
  scope :missing_documents, -> { where(ncr_data: { cloudinary_public_id: [nil, ''] }) }

  # --- Callbacks ---
  before_validation :set_ncr_number, if: :new_record?
  before_validation :set_defaults, if: :new_record?
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?

  # --- Display helpers ---

  def display_name
    "NCR#{hal_ncr_number}"
  end

  def display_title
    parts = ["NCR#{hal_ncr_number}"]
    parts << customer_name if customer_name.present?
    parts << part_display_name if part_display_name.present?
    parts << release_note_numbers
    parts.compact.join(" - ")
  end

  # --- Primary release note (first associated, for backward compat) ---

  def primary_release_note
    release_notes.order('external_ncr_release_notes.created_at ASC').first
  end

  # --- Data derived from release notes ---

  def batch_quantity_from_release_notes
    release_notes.sum { |rn| rn.quantity_accepted + rn.quantity_rejected }
  end

  # Backward compat alias
  alias_method :batch_quantity_from_release_note, :batch_quantity_from_release_notes

  def customer_po_numbers_from_works_orders
    release_notes.includes(works_order: :customer_order).map { |rn|
      rn.works_order&.customer_order&.number
    }.compact.uniq
  end

  def customer_po_number_from_works_order
    customer_po_numbers_from_works_orders.join(", ").presence
  end

  def customer_names
    release_notes.includes(works_order: :customer_order).map { |rn|
      rn.works_order&.customer_order&.customer&.name
    }.compact.uniq
  end

  def customer_name
    customer_names.join(", ").presence
  end

  def customers
    Organization.where(id:
      release_notes.includes(works_order: :customer_order)
                   .map { |rn| rn.works_order&.customer_order&.customer_id }
                   .compact.uniq
    )
  end

  # For the response PDF — use the first/primary customer
  def customer
    primary_release_note&.works_order&.customer_order&.customer
  end

  def part_display_names
    release_notes.includes(works_order: :part).map { |rn|
      rn.works_order&.part&.display_name
    }.compact.uniq
  end

  def part_display_name
    part_display_names.join(", ").presence
  end

  def part_numbers
    release_notes.includes(:works_order).map { |rn|
      "#{rn.works_order&.part_number}-#{rn.works_order&.part_issue}"
    }.compact.uniq
  end

  def part_number
    primary_release_note&.works_order&.part_number
  end

  def part_issue
    primary_release_note&.works_order&.part_issue
  end

  def part_description
    primary_release_note&.works_order&.part_description
  end

  def works_orders
    WorksOrder.where(id: release_notes.pluck(:works_order_id).uniq)
  end

  def works_order_numbers
    release_notes.includes(:works_order).map { |rn| rn.works_order&.display_name }.compact.uniq
  end

  def works_order_number
    works_order_numbers.join(", ").presence
  end

  # For backward compat (show page links etc.) — return first works order
  def works_order
    primary_release_note&.works_order
  end

  def release_note_numbers
    release_notes.map { |rn| "RN#{rn.number}" }.join(", ")
  end

  def release_note_number
    release_note_numbers
  end

  # --- Document management methods ---

  def has_document?
    cloudinary_public_id.present?
  end

  def document_filename
    original_filename.presence || "NCR#{hal_ncr_number}_incoming_document"
  end

  def document_size_formatted
    return nil unless file_size_bytes.present?

    bytes = file_size_bytes.to_i
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end

  def document_uploaded_date
    return nil unless document_uploaded_at.present?
    Time.parse(document_uploaded_at)
  rescue
    nil
  end

  def generate_cloudinary_download_url
    return nil unless has_document?

    begin
      CloudinaryService.generate_download_url(cloudinary_public_id)
    rescue => e
      Rails.logger.error "Failed to generate Cloudinary download URL for NCR #{hal_ncr_number}: #{e.message}"
      nil
    end
  end

  def can_replace_document?
    status == 'draft'
  end

  # Store document metadata after successful upload
  def store_document_metadata(upload_result)
    self.cloudinary_public_id = upload_result[:public_id]
    self.cloudinary_url = upload_result[:secure_url]
    self.original_filename = upload_result[:filename]
    self.file_size_bytes = upload_result[:size]
    self.content_type = upload_result[:content_type]
    self.document_uploaded_at = Time.current.iso8601
  end

  # --- Status management ---

  def next_status
    case status
    when 'draft' then 'in_progress'
    when 'in_progress' then 'completed'
    else nil
    end
  end

  def can_advance_status?
    case status
    when 'draft'
      description_of_non_conformance.present? && has_document?
    when 'in_progress'
      corrective_action.present? && preventive_action.present?
    else
      false
    end
  end

  def advance_status!
    return false unless can_advance_status?

    new_status = next_status
    return false unless new_status

    if new_status == 'completed'
      self.completed_by_user_id = Current.user&.id
    end

    update!(status: new_status)
  end

  # Status badge CSS class
  def status_badge_class
    case status
    when 'draft'
      'bg-gray-100 text-gray-800'
    when 'in_progress'
      'bg-yellow-100 text-yellow-800'
    when 'completed'
      'bg-green-100 text-green-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  # --- Search functionality ---

  def self.search(term)
    return all if term.blank?

    term = term.strip

    # Handle NCR prefix search (e.g., "NCR123" -> search for hal_ncr_number = 123)
    if term.match(/^NCR(\d+)$/i)
      ncr_number = term.match(/^NCR(\d+)$/i)[1].to_i
      return where(hal_ncr_number: ncr_number)
    end

    # General search across associated release notes
    joins(release_notes: { works_order: :customer_order })
      .joins("LEFT JOIN organizations ON customer_orders.customer_id = organizations.id")
      .where(
        "CAST(hal_ncr_number AS TEXT) ILIKE ? OR " \
        "organizations.name ILIKE ? OR " \
        "works_orders.part_number ILIKE ? OR " \
        "(ncr_data->>'original_filename') ILIKE ?",
        "%#{term}%", "%#{term}%", "%#{term}%", "%#{term}%"
      )
      .distinct
  end

  # --- Replace document (for draft NCRs only) ---

  def replace_document!(new_upload_result)
    raise "Cannot replace document for non-draft NCR" unless can_replace_document?

    # Delete old document from Cloudinary if it exists
    if cloudinary_public_id.present?
      begin
        CloudinaryService.delete_file(cloudinary_public_id)
      rescue => e
        Rails.logger.error "Failed to delete old Cloudinary document: #{e.message}"
      end
    end

    # Store new document metadata and save
    store_document_metadata(new_upload_result)
    save!
  end

  private

  def at_least_one_release_note
    # Check both the association and any pending IDs
    if release_notes.empty? && external_ncr_release_notes.empty?
      errors.add(:base, "At least one release note is required")
    end
  end

  def set_ncr_number
    sequence = Sequence.find_or_create_by(key: 'external_ncr_number')
    self.hal_ncr_number = sequence.value
    sequence.increment!(:value)
  end

  def set_defaults
    self.date ||= Date.current
    self.status ||= 'draft'
    self.ncr_data ||= {}
    # Auto-assign respondent to creator
    self.respondent = created_by if created_by.present?
  end

  def log_creation
    rn_numbers = release_notes.map(&:number).join(", ")
    Rails.logger.info "Created External NCR #{hal_ncr_number} for Release Notes: #{rn_numbers}"
  end

  def log_status_change
    Rails.logger.info "External NCR #{hal_ncr_number} status changed from #{status_before_last_save} to #{status}"
  end
end
