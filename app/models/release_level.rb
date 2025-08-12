# app/models/release_level.rb
class ReleaseLevel < ApplicationRecord
  has_many :works_orders, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :statement, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :ordered, -> { order(:name) }

  after_initialize :set_defaults, if: :new_record?

  def display_name
    name
  end

  def can_be_deleted?
    works_orders.empty?
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
    self.statement = "" if statement.blank?
  end
end
