class Part < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  has_many :part_processing_instructions, dependent: :restrict_with_error
  has_many :works_orders, dependent: :restrict_with_error
  has_many :release_notes, through: :works_orders

  validates :uniform_part_number, presence: true
  validates :uniform_part_issue, presence: true
  validates :uniform_part_number, uniqueness: {
    scope: [:customer_id, :uniform_part_issue],
    message: "and issue must be unique per customer"
  }

  scope :enabled, -> { where(enabled: true) }
  scope :for_customer, ->(customer) { where(customer: customer) }

  before_validation :normalize_part_details
  after_initialize :set_defaults, if: :new_record?

  # Make text uniform (uppercase, alphanumeric only)
  def self.make_uniform(text)
    return "" if text.nil?
    # Remove accents and convert to ASCII
    text = text.unicode_normalize(:nfd).encode('ASCII', undef: :replace, replace: '').upcase
    # Keep only alphanumeric characters
    text.gsub(/[^A-Z0-9]/, '')
  end

  # Find or create a part
  def self.ensure(customer_id:, part_number:, part_issue:)
    uniform_number = make_uniform(part_number)
    uniform_issue = make_uniform(part_issue)

    find_or_create_by(
      customer_id: customer_id,
      uniform_part_number: uniform_number,
      uniform_part_issue: uniform_issue
    )
  end

  # Query helper for matching parts
  def self.matching(customer_id: nil, part_number: nil, part_issue: nil)
    scope = all
    scope = scope.where(customer_id: customer_id) if customer_id
    scope = scope.where(uniform_part_number: make_uniform(part_number)) if part_number
    scope = scope.where(uniform_part_issue: make_uniform(part_issue)) if part_issue
    scope
  end

  def display_name
    "#{uniform_part_number}-#{uniform_part_issue}"
  end

  def can_be_deleted?
    part_processing_instructions.empty? && works_orders.empty?
  end

  private

  def normalize_part_details
    self.uniform_part_number = self.class.make_uniform(uniform_part_number)
    self.uniform_part_issue = self.class.make_uniform(uniform_part_issue)
  end

  def set_defaults
    self.enabled = true if enabled.nil?
    self.uniform_part_issue = 'A' if uniform_part_issue.blank?
  end
end
