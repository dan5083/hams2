# app/models/external_ncr_note.rb
#
# Internal background on an NCR: what happened on the floor, who's looked at
# it, why it's taking longer than it should. Anyone logged in can add one.
# Never rendered on the customer response document.
class ExternalNcrNote < ApplicationRecord
  belongs_to :external_ncr, inverse_of: :notes
  belongs_to :user

  validates :body, presence: true

  scope :newest_first, -> { order(created_at: :desc) }

  # Author can bin their own note; NCR managers can bin any.
  def deletable_by?(someone)
    return false if someone.nil?
    someone.can_manage_ncrs? || user_id == someone.id
  end
end
