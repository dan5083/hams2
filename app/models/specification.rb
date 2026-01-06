# app/models/specification.rb
class Specification < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :updated_by, class_name: 'User', optional: true

  # JSONB accessors for document storage (like NCRs)
  store_accessor :document_data,
    :cloudinary_public_id,
    :cloudinary_url,
    :original_filename,
    :file_size_bytes,
    :content_type,
    :document_uploaded_at

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :is_qs, inclusion: { in: [true, false] }
  validates :version, length: { maximum: 50 }, allow_blank: true
  validates :created_by_id, presence: true

  # Scopes
  scope :qs_specs, -> { where(is_qs: true) }
  scope :non_qs_specs, -> { where(is_qs: false) }
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults, if: :new_record?
  after_create :log_creation

  def display_name
    title
  end

  def spec_type
    is_qs? ? "QS" : "Non-QS"
  end

  def spec_type_badge_class
    is_qs? ? 'bg-purple-100 text-purple-800' : 'bg-blue-100 text-blue-800'
  end

  # Document management methods
  def has_document?
    cloudinary_public_id.present?
  end

  def document_filename
    original_filename.presence || "#{display_name.parameterize}"
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
      Rails.logger.error "Failed to generate Cloudinary download URL for Spec #{id}: #{e.message}"
      nil
    end
  end

  def can_edit_document?
    !archived?
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

  # Replace document
  def replace_document!(new_upload_result)
    raise "Cannot replace document for archived specification" if archived?

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

  # Archive/Unarchive
  def archive!
    update!(archived: true)
  end

  def unarchive!
    update!(archived: false)
  end

  # Search functionality
  def self.search(term)
    return all if term.blank?

    term = term.strip

    where(
      "title ILIKE ? OR " \
      "description ILIKE ? OR " \
      "(document_data->>'original_filename') ILIKE ?",
      "%#{term}%", "%#{term}%", "%#{term}%"
    )
  end

  private

  def set_defaults
    self.archived = false if archived.nil?
    self.is_qs = false if is_qs.nil?
    self.document_data ||= {}
  end

  def log_creation
    Rails.logger.info "Created Specification: #{display_name} (#{spec_type})"
  end
end
