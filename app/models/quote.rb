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

  belongs_to :customer, class_name: "Organization"
  belongs_to :created_by, class_name: "User", optional: true
  has_many :quote_items, -> { order(:position) }, dependent: :destroy, inverse_of: :quote
  has_many :parts, through: :quote_items

  validates :number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :enquirer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :assign_next_number, if: :new_record?
  before_validation -> { self.valid_until ||= Date.current + 30.days }, if: :new_record?
  before_create -> { self.created_by ||= Current.user }

  scope :recent, -> { order(created_at: :desc) }
  scope :open,   -> { where(status: %w[draft sent]) }

  def in_workbench? = WORKBENCH_STATUSES.include?(status)
  def proposing?    = status == "proposing"
  def proposed?     = status == "proposed"

  def proposal_questions = Array(proposal&.dig("questions"))
  def proposal_parts     = Array(proposal&.dig("parts"))
  def proposal_lines     = Array(proposal&.dig("lines"))

  def self.next_number
    Sequence.next_value("quote_number")
  end

  def display_name
    "QT#{number}"
  end

  def total_ex_tax
    quote_items.sum { |i| i.line_total }
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
