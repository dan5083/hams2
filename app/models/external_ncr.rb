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

  # Temporary file upload for processing before Dropbox upload
  has_one_attached :temp_document

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

    # Dropbox document storage
    :dropbox_file_path,
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

  # Validate temp document for new records
  validates :temp_document, presence: true, on: :create, unless: :has_document?

  # Scopes
  scope :active, -> { where.not(status: 'completed') }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_customer, ->(customer) { joins(:customer).where(customer: customer) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_documents, -> { where.not(ncr_data: { dropbox_file_path: [nil, ''] }) }
  scope :missing_documents, -> { where(ncr_data: { dropbox_file_path: [nil, ''] }) }

  # Callbacks
  before_validation :set_ncr_number, if: :new_record?
  before_validation :set_defaults, if: :new_record?
  after_create :upload_document_to_dropbox, if: -> { temp_document.attached? }
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
    dropbox_file_path.present? || temp_document.attached?
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
      DropboxNcrService.generate_download_link(dropbox_file_path)
    rescue => e
      Rails.logger.error "Failed to generate Dropbox download URL for NCR #{hal_ncr_number}: #{e.message}"
      nil
    end
  end

  def can_replace_document?
    status == 'draft'
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
  def replace_document!(new_file)
    raise "Cannot replace document for non-draft NCR" unless can_replace_document?

    # Delete old document from Dropbox if it exists
    if has_document?
      DropboxNcrService.delete_document(dropbox_file_path)
    end

    # Clear existing document data
    self.dropbox_file_path = nil
    self.original_filename = nil
    self.file_size_bytes = nil
    self.content_type = nil
    self.document_uploaded_at = nil

    # Attach new temporary file
    self.temp_document = new_file

    if save
      upload_document_to_dropbox
      true
    else
      false
    end
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

  def upload_document_to_dropbox
    return unless temp_document.attached?

    Rails.logger.info "Uploading document to Dropbox for NCR #{hal_ncr_number}"

    begin
      # Extract file information
      attachment = temp_document.attachment
      blob = attachment.blob

      # Store file metadata
      self.original_filename = blob.filename.to_s
      self.file_size_bytes = blob.byte_size
      self.content_type = blob.content_type

      # Upload to Dropbox
      file_path = DropboxNcrService.upload_document(self, temp_document)

      if file_path
        self.dropbox_file_path = file_path
        self.document_uploaded_at = Time.current.iso8601
        save!

        # Clean up temporary file
        temp_document.purge

        Rails.logger.info "Successfully uploaded NCR #{hal_ncr_number} document to Dropbox: #{file_path}"
      else
        Rails.logger.error "Failed to upload NCR #{hal_ncr_number} document to Dropbox"
      end

    rescue => e
      Rails.logger.error "Error uploading NCR #{hal_ncr_number} document: #{e.message}"
      # Don't fail the NCR creation, but log the error
    end
  end

  def log_creation
    Rails.logger.info "Created External NCR #{hal_ncr_number} for Release Note #{release_note.number}"
  end

  def log_status_change
    Rails.logger.info "External NCR #{hal_ncr_number} status changed from #{status_before_last_save} to #{status}"
  end
end
