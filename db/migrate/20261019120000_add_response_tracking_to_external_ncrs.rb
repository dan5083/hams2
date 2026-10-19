class AddResponseTrackingToExternalNcrs < ActiveRecord::Migration[8.0]
  def change
    # `date` is already "date received". These two give us the timer and the
    # on-time measurement the consultant is going to ask for next.
    add_column :external_ncrs, :target_response_date, :date
    add_column :external_ncrs, :responded_at, :datetime
    add_index  :external_ncrs, :target_response_date

    # Internal, timestamped background notes. Deliberately a separate table
    # rather than another ncr_data key: ncr_data feeds the customer response
    # PDF and these must never appear on it.
    create_table :external_ncr_notes, id: :uuid do |t|
      t.references :external_ncr, null: false, foreign_key: true, type: :uuid
      t.references :user,         null: false, foreign_key: true, type: :uuid
      t.text :body, null: false
      t.timestamps
    end
  end
end
