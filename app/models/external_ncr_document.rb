# app/models/external_ncr_document.rb
class ExternalNcrDocument < ApplicationRecord
  belongs_to :external_ncr, inverse_of: :documents
  belongs_to :uploaded_by, class_name: 'User'

  # Key => human label. Order here is the order shown in the dropdown.
  DOCUMENT_TYPES = {
    'incoming_ncr' => 'Incoming NCR document',
    'email'        => 'Email correspondence',
    'evidence'     => 'Photo / evidence',
    'response'     => 'Our response to customer',
    'other'        => 'Other'
  }.freeze

  validates :document_type, inclusion: { in: DOCUMENT_TYPES.keys }
  validates :cloudinary_public_id, presence: true

  scope :chronological, -> { order(:uploaded_at) }
  scope :incoming,      -> { where(document_type: 'incoming_ncr') }
  scope :emails,        -> { where(document_type: 'email') }

  before_validation :set_uploaded_at, on: :create
  before_destroy :remove_from_cloudinary

  def type_label
    DOCUMENT_TYPES[document_type] || 'Document'
  end

  def filename
    original_filename.presence || "NCR#{external_ncr&.hal_ncr_number}_document"
  end

  def size_formatted
    return nil if file_size_bytes.blank?

    bytes = file_size_bytes.to_i
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end

  def download_url
    CloudinaryService.generate_download_url(cloudinary_public_id)
  rescue => e
    Rails.logger.error "Failed to generate Cloudinary download URL for NCR document #{id}: #{e.message}"
    nil
  end

  private

  def set_uploaded_at
    self.uploaded_at ||= Time.current
  end

  # Fires via dependent: :destroy on ExternalNcr too, so binning an NCR
  # cleans up every stored file without the controller doing anything.
  def remove_from_cloudinary
    return if cloudinary_public_id.blank?

    CloudinaryService.delete_file(cloudinary_public_id)
  rescue => e
    Rails.logger.error "Failed to delete Cloudinary file #{cloudinary_public_id}: #{e.message}"
  end
end
