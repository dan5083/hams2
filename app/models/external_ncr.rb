# app/models/external_ncr.rb
class ExternalNcr < ApplicationRecord
  belongs_to :release_note
  belongs_to :created_by, class_name: 'User'
  belongs_to :respondent, class_name: 'User', foreign_key: 'assigned_to_id'

  # Delegate common fields to release_note -> works_order for easy access
  has_one :works_order, through: :release_note
  has_one :customer_order, through: :works_order
  has_one :customer, through: :customer_order
  has_one :part, through: :works_order

  # JSONB accessors for NCR-specific data
  store_accessor :ncr_data,
    # Identification numbers
    :concession_number,
    :customer_ncr_number,
    :estimated_cost,

    # Quantities
    :reject_quantity,

    # NCR Content
    :description_of_non_conformance,
    :investigation_root_cause_analysis,
    :root_cause_identified,
    :containment_corrective_action,
    :preventive_action,
    :completed_by_user_id,

    # Cloudinary document storage
    :cloudinary_public_id,
    :cloudinary_url,
    :original_filename,
    :file_size_bytes,
    :content_type,
    :document_uploaded_at

  # Validations
  validates :hal_ncr_number, presence: true, uniqueness: true, numericality: { greater_than: 0 }
  validates :release_note_id, presence: true
  validates :date, presence: true
  validates :created_by_id, presence: true
  validates :status, inclusion: { in: %w[draft in_progress completed] }

  # Validate quantities if provided
  validates :reject_quantity, numericality: { greater_than: 0 }, allow_blank: true
  validates :estimated_cost, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true

  # Scopes
  scope :active, -> { where.not(status: 'completed') }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_customer, ->(customer) { joins(:customer).where(customer: customer) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_documents, -> { where.not(ncr_data: { cloudinary_public_id: [nil, ''] }) }
  scope :missing_documents, -> { where(ncr_data: { cloudinary_public_id: [nil, ''] }) }

  # Callbacks
  before_validation :set_ncr_number, if: :new_record?
  before_validation :set_defaults, if: :new_record?
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?

  def display_name
    "NCR#{hal_ncr_number}"
  end

  def display_title
    "NCR#{hal_ncr_number} - #{customer_name} - #{part_display_name} - RN#{release_note.number}"
  end

  # Auto-populated data from release note
  def batch_quantity_from_release_note
    return nil unless release_note
    release_note.quantity_accepted + release_note.quantity_rejected
  end

  def customer_po_number_from_works_order
    works_order&.customer_order&.number
  end

  def customer_name
    customer&.name
  end

  def part_display_name
    works_order&.part&.display_name
  end

  def part_number
    works_order&.part_number
  end

  def part_issue
    works_order&.part_issue
  end

  def part_description
    works_order&.part_description
  end

  def works_order_number
    works_order&.display_name
  end

  def release_note_number
    "RN#{release_note.number}"
  end

  # Document management methods
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

  def generate_dropbox_download_url
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

  # Status management
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
      containment_corrective_action.present? && preventive_action.present?
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

  # Search functionality
  def self.search(term)
    return all if term.blank?

    term = term.strip

    # Handle NCR prefix search (e.g., "NCR123" -> search for hal_ncr_number = 123)
    if term.match(/^NCR(\d+)$/i)
      ncr_number = term.match(/^NCR(\d+)$/i)[1].to_i
      return where(hal_ncr_number: ncr_number)
    end

    # General search
    joins(release_note: { works_order: :customer_order })
      .joins(customer: [])
      .where(
        "CAST(hal_ncr_number AS TEXT) ILIKE ? OR " \
        "organizations.name ILIKE ? OR " \
        "works_orders.part_number ILIKE ? OR " \
        "(ncr_data->>'original_filename') ILIKE ?",
        "%#{term}%", "%#{term}%", "%#{term}%", "%#{term}%"
      )
      .distinct
  end

  # Replace document (for draft NCRs only)
  def replace_document!(new_upload_result)
    raise "Cannot replace document for non-draft NCR" unless can_replace_document?

    # Delete old document from Cloudinary if it exists
    if cloudinary_public_id.present?
      begin
        CloudinaryService.delete_file(cloudinary_public_id)
      rescue => e
        Rails.logger.error "Failed to delete old Cloudinary document: #{e.message}"
        # Continue with replacement even if deletion fails
      end
    end

    # Store new document metadata and save
    store_document_metadata(new_upload_result)
    save!
  end

  private

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
    Rails.logger.info "Created External NCR #{hal_ncr_number} for Release Note #{release_note.number}"
  end

  def log_status_change
    Rails.logger.info "External NCR #{hal_ncr_number} status changed from #{status_before_last_save} to #{status}"
  end
end
