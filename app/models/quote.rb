# app/models/quote.rb
#
# A quotation raised by HAMS (normally by the AI assistant from a drawing or
# enquiry) and emailed to the enquirer. Replaces the old draft-quote push to
# Xero. Each line is a QuoteItem, normally tied to a Part that was created
# (or found) at quote time with the drawing already attached — so when the
# PO arrives, booking in is a lookup, not a data-entry job.
#
# Status:
#   proposing        — workbench: QuoteProposalJob is running
#   proposed         — workbench: proposal ready for review (or re-run)
#   proposal_failed  — workbench: job errored; proposal_error says why
#   draft            — saved: parts + items exist, nothing sent
#   sent -> won | lost
class Quote < ApplicationRecord
  STATUSES          = %w[proposing proposed proposal_failed draft sent won lost].freeze
  WORKBENCH_STATUSES = %w[proposing proposed proposal_failed].freeze

  # Unset while the assistant is working out who the customer is; required
  # from draft onwards (finalise resolves it from the reviewed form).
  belongs_to :customer, class_name: "Organization", optional: true
  validates :customer, presence: true, unless: :in_workbench?
  belongs_to :created_by, class_name: "User", optional: true
  has_many :quote_items, -> { order(:position) }, dependent: :destroy, inverse_of: :quote
  has_many :parts, through: :quote_items

  validates :number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :enquirer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :assign_next_number, if: :new_record?
  VALIDITY_DAYS = 90
  before_validation -> { self.valid_until ||= Date.current + VALIDITY_DAYS.days }, if: :new_record?
  before_create -> { self.created_by ||= Current.user }

  scope :recent, -> { order(created_at: :desc) }
  scope :open,   -> { where(status: %w[draft sent]) }

  def in_workbench? = WORKBENCH_STATUSES.include?(status)
  def proposing?    = status == "proposing"
  def proposed?     = status == "proposed"

  def proposal_questions = Array(proposal&.dig("questions"))
  def proposal_parts     = Array(proposal&.dig("parts"))
  def proposal_lines     = Array(proposal&.dig("lines"))
  def proposal_prime     = proposal&.dig("end_user_prime").presence
  def prime_uplift       = proposal&.dig("prime_uplift").to_f

  def self.next_number
    Sequence.next_value("quote_number")
  end

  def display_name
    "QT#{number}"
  end

  def total_ex_tax
    quote_items.sum { |i| i.line_total }
  end

  # What the customer sees. The saved quote_items keep the breakdown for us
  # (one per treatment, one for masking); the customer gets ONE row per part
  # with those per-piece amounts summed into a single each price — the same
  # figure saved as the part's each_price. Price breaks (same part, different
  # quantity) stay separate rows; the MOC and any other part-less line is its
  # own row. Order follows the items' positions.
  CustomerLine = Struct.new(:part, :description, :quantity, :unit_amount, :items, keyword_init: true) do
    def line_total = unit_amount * quantity
    def combined?  = items.size > 1
  end

  def customer_lines
    quote_items.includes(:part)
               .group_by { |i| i.part_id ? [i.part_id, i.quantity] : [nil, i.id] }
               .map do |_, items|
      CustomerLine.new(
        part:        items.first.part,
        description: items.map { |i| i.description.to_s.strip }.join("\n"),
        quantity:    items.first.quantity,
        unit_amount: items.sum(&:unit_amount),
        items:       items
      )
    end
  end

  def sent?  = status == "sent"
  def draft? = status == "draft"

  def can_send?
    enquirer_email.present? && quote_items.any?
  end

  # Drawings to go out with the quote: every previewable file on every part
  # on the quote, de-duplicated by Cloudinary id. [{ part:, index: }]
  def attachable_part_files
    seen = {}
    quote_items.includes(:part).filter_map do |item|
      part = item.part
      next unless part
      part.files.each_index.filter_map do |i|
        id = part.files[i]["cloudinary_public_id"]
        next if id.blank? || seen[id]
        seen[id] = true
        { part: part, index: i }
      end
    end.flatten
  end

  private

  def assign_next_number
    self.number ||= self.class.next_number
  end
end
