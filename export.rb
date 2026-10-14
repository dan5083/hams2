require "csv"

csv = CSV.generate do |out|
  out << %w[works_order part_no part_description price date_released qty]
  WorksOrder.where(voided: false).order(:number).find_each do |wo|
    released = wo.release_notes.active.maximum(:created_at)
    out << [wo.number, wo.part_number, wo.part_description,
            wo.total_price.to_f.round(2), released&.to_date, wo.quantity]
  end
end

$stdout.write csv
