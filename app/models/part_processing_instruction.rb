# app/models/part_processing_instruction.rb
class PartProcessingInstruction < ApplicationRecord
  belongs_to :part
  belongs_to :customer, class_name: 'Organization'
  belongs_to :replaces, class_name: 'PartProcessingInstruction', optional: true

  has_many :works_orders, foreign_key: :ppi_id, dependent: :restrict_with_error
  has_many :replaced_by, class_name: 'PartProcessingInstruction',
           foreign_key: :replaces_id, dependent: :nullify

  validates :part_number, presence: true
  validates :part_issue, presence: true
  validates :part_description, presence: true
  validates :specification, presence: true
  validates :process_type, inclusion: { in: ProcessBuilder.available_types }
  # Temporarily removed for testing: validates :customisation_data, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :for_part_number, ->(part_number) { where("part_number ILIKE ?", "%#{part_number}%") }
  scope :for_part_issue, ->(part_issue) { where("part_issue ILIKE ?", "%#{part_issue}%") }

  before_validation :set_part_from_details, if: :part_details_changed?
  after_initialize :set_defaults, if: :new_record?
  after_create :disable_replaced_ppi

  def self.create_from_data(data, user = nil)
    # Ensure we have a part record
    part = Part.ensure(
      customer_id: data[:customer_id],
      part_number: data[:part_number],
      part_issue: data[:part_issue]
    )

    ppi = new(data.merge(part: part))
    ppi.save!
    ppi
  end

  def self.search(customer_id: nil, part_number: nil, part_issue: nil, only_enabled: true)
    scope = all
    scope = scope.for_customer(customer_id) if customer_id
    scope = scope.for_part_number(part_number) if part_number
    scope = scope.for_part_issue(part_issue) if part_issue
    scope = scope.enabled if only_enabled
    scope
  end

  def display_name
    "#{part_number}-#{part_issue}"
  end

  def enable!
    update!(enabled: true)
  end

  def disable!
    update!(enabled: false)
  end

  def can_be_deleted?
    works_orders.empty? && replaced_by.empty?
  end

  def build_customised_process
    return {} unless process_type.present? && customisation_data.present?
    ProcessBuilder.build_process(process_type, customisation_data, part: part)
  end

  def process_builder
    @process_builder ||= ProcessBuilder.for_type(process_type)
  end

  def available_customizations
    process_builder&.available_customizations || {}
  end

  def active?
    enabled && part&.enabled && customer&.active?
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.customisation_data = {} if customisation_data.blank?
  end

  def part_details_changed?
    part_number_changed? || part_issue_changed? || customer_id_changed?
  end

  def set_part_from_details
    return unless part_number.present? && part_issue.present? && customer_id.present?

    self.part = Part.ensure(
      customer_id: customer_id,
      part_number: part_number,
      part_issue: part_issue
    )
  end

  def disable_replaced_ppi
    return unless replaces_id.present?
    replaces&.disable!
  end
end
