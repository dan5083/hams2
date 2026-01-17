# app/models/skipton_customer_mapping.rb
class SkiptonCustomerMapping < ApplicationRecord
  validates :xero_name, presence: true, uniqueness: { case_sensitive: true }
  validates :skipton_id, presence: true

  # Normalize whitespace on save
  before_validation :normalize_names

  # Main lookup method - what SkiptonExportService will use
  def self.find_skipton_id(xero_name)
    return nil if xero_name.blank?
    find_by(xero_name: xero_name&.strip)&.skipton_id
  end

  # Bulk lookup - returns a hash for efficient lookups
  def self.mapping_hash
    all.pluck(:xero_name, :skipton_id).to_h
  end

  # Check if a Xero customer is mapped
  def self.mapped?(xero_name)
    exists?(xero_name: xero_name&.strip)
  end

  # Get all unmapped customers from invoices
  def self.unmapped_invoice_customers
    Invoice.joins(:customer)
           .distinct
           .pluck('organizations.name')
           .reject { |name| mapped?(name) }
           .sort
  end

  private

  def normalize_names
    self.xero_name = xero_name&.strip
    self.skipton_id = skipton_id&.strip
  end
end
