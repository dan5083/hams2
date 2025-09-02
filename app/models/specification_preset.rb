# app/models/specification_preset.rb
class SpecificationPreset < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :content, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :ordered, -> { order(:name) }

  after_initialize :set_defaults, if: :new_record?

  def display_name
    name
  end

  def can_be_deleted?
    # Add logic here if specifications get referenced elsewhere
    true
  end

  def enable!
    update!(enabled: true)
  end

  def disable!
    update!(enabled: false)
  end

  def active?
    enabled
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
