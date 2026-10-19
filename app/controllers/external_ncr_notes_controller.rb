# app/controllers/external_ncr_notes_controller.rb
class ExternalNcrNotesController < ApplicationController
  before_action :set_external_ncr, only: [:create]
  before_action :set_note,         only: [:destroy]

  def create
    note = @external_ncr.notes.build(note_params.merge(user: Current.user))

    if note.save
      redirect_to @external_ncr, notice: 'Note added.'
    else
      redirect_to @external_ncr, alert: note.errors.full_messages.to_sentence
    end
  end

  def destroy
    ncr = @note.external_ncr

    unless @note.deletable_by?(Current.user)
      redirect_to ncr, alert: 'You can only remove your own notes.'
      return
    end

    @note.destroy
    redirect_to ncr, notice: 'Note removed.'
  end

  private

  def set_external_ncr
    @external_ncr = ExternalNcr.find(params[:external_ncr_id])
  end

  def set_note
    @note = ExternalNcrNote.find(params[:id])
  end

  def note_params
    params.require(:external_ncr_note).permit(:body)
  end
end
