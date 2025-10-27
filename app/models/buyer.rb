# app/models/buyer.rb
class Buyer < ApplicationRecord
  belongs_to :organization

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :organization_id, message: "already exists for this organization" }

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  # Default enabled to true for new buyers
  after_initialize :set_defaults, if: :new_record?

  def display_name
    email
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
