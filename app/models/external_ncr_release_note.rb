# app/models/external_ncr_release_note.rb
class ExternalNcrReleaseNote < ApplicationRecord
  belongs_to :external_ncr
  belongs_to :release_note

  validates :release_note_id, uniqueness: { scope: :external_ncr_id, message: "has already been added to this NCR" }
end
