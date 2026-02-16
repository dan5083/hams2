# app/models/quality_document.rb
class QualityDocument < ApplicationRecord
  has_many :revisions, class_name: 'QualityDocumentRevision', dependent: :destroy

  # Skip revision tracking during migration
  attr_accessor :skip_revision_tracking

  # Reissue metadata (set by controller from modal form)
  attr_accessor :reissue_change_description, :reissue_authorised_by

  DOCUMENT_TYPES = {
    'IP' => 'Integrated Procedure',
    'WI' => 'Works Instruction',
    'PCD' => 'Process Control',
    'F' => 'Form',
    'PM' => 'Process Mapping Process',
    'IM' => 'Integrated Manual'
  }.freeze

  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES.keys }
  validates :code, presence: true, uniqueness: { scope: :document_type }
  validates :title, presence: true
  validates :current_issue_number, presence: true, numericality: { greater_than: 0 }

  before_update :create_revision_if_content_changed

  def full_code
    "#{document_type} #{code}"
  end

  def type_description
    DOCUMENT_TYPES[document_type]
  end

  # Initialize with default sections structure if needed
  def content
    super.presence || default_content_structure
  end

  private

  def default_content_structure
    {
      'sections' => [],
      'references' => []
    }
  end

  def create_revision_if_content_changed
    # Skip revision creation during migration
    return if skip_revision_tracking

    # Only create revision if issue number actually changed (reissue)
    if current_issue_number_changed?
      revisions.create!(
        issue_number: current_issue_number,
        changed_by: reissue_authorised_by.presence || Current.user&.display_name || 'System',
        changed_at: Time.current,
        previous_content: content_was,
        change_description: reissue_change_description.presence || "Updated to issue #{current_issue_number}"
      )
    end
  end
end

# app/models/quality_document_revision.rb
class QualityDocumentRevision < ApplicationRecord
  belongs_to :quality_document

  validates :issue_number, presence: true
  validates :changed_by, presence: true
  validates :changed_at, presence: true
end
