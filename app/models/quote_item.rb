# app/models/quote_item.rb
class QuoteItem < ApplicationRecord
  belongs_to :quote, inverse_of: :quote_items
  belongs_to :part, optional: true

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_amount, numericality: { greater_than_or_equal_to: 0 }

  before_validation :set_position, if: :new_record?

  def line_total
    (unit_amount || 0) * (quantity || 0)
  end

  private

  def set_position
    self.position ||= (quote.quote_items.maximum(:position) || -1) + 1 if quote
  end
end
