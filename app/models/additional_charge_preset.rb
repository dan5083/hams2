# app/models/additional_charge_preset.rb
class AdditionalChargePreset < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }, unless: :is_variable
  validates :calculation_type, inclusion: { in: %w[fixed weight_based variable weight_based_next_day weight_based_premium] }, allow_blank: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :fixed, -> { where(is_variable: false) }
  scope :variable, -> { where(is_variable: true) }
  scope :ordered, -> { order(:name) }

  after_initialize :set_defaults, if: :new_record?

  # Charge presets whose names indicate carriage even when priced as 'fixed'
  # (e.g. a flat "Courier - Next Day" preset).
  CARRIAGE_NAME_PATTERN = /courier|carriage|shipping|postage|freight|dispatch|delivery/i

  # Is this charge a carriage/courier charge (as opposed to e.g. rework or
  # masking)? Used by the order-complete email to decide between "ready to
  # collect" and "dispatching by courier". All weight_based* calculation
  # types are carriage by definition; fixed/variable presets fall back to a
  # name match.
  def carriage?
    calculation_type.to_s.start_with?('weight_based') ||
      name.to_s.match?(CARRIAGE_NAME_PATTERN)
  end

  def display_name
    if is_variable?
      "#{name} (Variable)"
    elsif amount.present?
      "#{name} - £#{sprintf('%.2f', amount)}"
    else
      name
    end
  end

  def can_be_deleted?
    # Add logic here if charges get referenced elsewhere (e.g., in invoices)
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

  def formatted_amount
    return 'Variable' if is_variable? || amount.blank?
    "£#{sprintf('%.2f', amount)}"
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.is_variable = false if is_variable.nil?
    self.calculation_type = 'fixed' if calculation_type.blank? && !is_variable?
  end
end
