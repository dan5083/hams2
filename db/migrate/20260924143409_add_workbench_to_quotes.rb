class AddWorkbenchToQuotes < ActiveRecord::Migration[8.0]
  def change
    change_table :quotes do |t|
      t.text     :enquiry                                  # pasted enquiry / email text
      t.jsonb    :drawings,       null: false, default: [] # uploaded files (Cloudinary), copied onto parts on save
      t.jsonb    :proposal                                 # QuoteProposalJob output
      t.jsonb    :answers,        null: false, default: {} # reviewer's answers to proposal questions
      t.text     :proposal_error
      t.datetime :proposed_at
    end
  end
end
