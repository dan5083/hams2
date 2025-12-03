# FYI to see decluttered tree use:
tree -I "node_modules|.git|.DS_Store|*.log|coverage|build|dist|tmp"
<<<<<<< HEAD
=======

<!-- HOW TO GET UNINVOICED RELEASE LIST -->

require 'csv'

# Find all release notes with accepted quantity that haven't been invoiced
uninvoiced = ReleaseNote.where(voided: false, no_invoice: false)
  .where('quantity_accepted > 0')
  .where.not(id: InvoiceItem.select(:release_note_id).where.not(release_note_id: nil))
  .includes(works_order: [:part, customer_order: :customer])
  .order(:number)

# Generate CSV
csv_output = CSV.generate do |csv|
  # Header row
  csv << ['RN Number', 'RN Date', 'WO Number', 'Customer Order', 'Customer', 'Part Number', 'Part Issue', 'Description', 'Qty Accepted', 'Qty Rejected', 'Each Price', 'Line Total', 'Partial Release']

  # Data rows
  uninvoiced.each do |rn|
    wo = rn.works_order
    co = wo.customer_order
    customer = co.customer

    line_total = (wo.price_per_unit * rn.quantity_accepted).round(2)
    partial_release = wo.quantity_released < wo.quantity

    csv << [
      rn.number,
      rn.date,
      wo.number,
      co.number,
      customer.name,
      wo.part_number,
      wo.part_issue,
      wo.part_description,
      rn.quantity_accepted,
      rn.quantity_rejected,
      wo.price_per_unit.round(2),
      line_total,
      partial_release
    ]
  end
end

puts csv_output
puts "\n=== SUMMARY ==="
puts "Total uninvoiced release notes: #{uninvoiced.count}"
puts "Total uninvoiced quantity: #{uninvoiced.sum(:quantity_accepted)}"
puts "Total value: £#{uninvoiced.sum { |rn| rn.works_order.price_per_unit * rn.quantity_accepted }.round(2)}"


<!-- HOW TO CHANGE LUFTHANSA MISSING MFT TO CHROMIC  -->

customer = Organization.find_by("name ILIKE ?", "%Lufthansa Technik%")
raise "Customer not found" unless customer

fixed = 0

Part.where(customer: customer, enabled: true).find_each do |part|
  next unless part.aerospace_defense?
  next unless part.locked_for_editing?

  treatments_json = part.customisation_data.dig("operation_selection", "treatments")
  treatments = if treatments_json.is_a?(String)
    JSON.parse(treatments_json) rescue []
  else
    treatments_json || []
  end

  next if treatments.any?

  has_chromic = part.locked_operations.any? do |op|
    text = "#{op['operation_text']} #{op['display_name']}".downcase
    text.include?("chromic") && text.include?("anodis")
  end

  next unless has_chromic

  part.customisation_data['operation_selection']['treatments'] = [
    {
      'type' => 'chromic_anodising',
      'operation_id' => 'CHROMIC_22V',
      'selected_jig_type' => 'titanium_wire',
      'target_thickness' => 5
    }
  ].to_json

  if part.save
    puts "✅ #{part.part_number}"
    fixed += 1
  else
    puts "❌ #{part.part_number}"
  end
end

puts ""
puts "Fixed #{fixed} parts"
>>>>>>> 1cf67547f663154849569088241942f04c51e7dc


<!-- HOW TO GET CHRIS"S ORDER COMPLETION REPORT -->

heroku run rails runner "$(cat <<'EOF'
require 'csv'

def working_days_between(start_date, end_date)
  return 0 if end_date.nil? || start_date.nil?
  return 0 if end_date < start_date
  days = 0
  current_date = start_date
  while current_date <= end_date
    days += 1 if current_date.wday.between?(1, 5)
    current_date += 1
  end
  days
end

october_start = Date.new(2025, 10, 1)
october_end = Date.new(2025, 10, 31)

customer_orders = CustomerOrder.includes(:customer, works_orders: [:part, :release_notes])
                                .where(voided: false)
                                .where(date_received: october_start..october_end)
                                .order(Arel.sql('CASE WHEN EXISTS (SELECT 1 FROM works_orders wo JOIN release_notes rn ON rn.works_order_id = wo.id WHERE wo.customer_order_id = customer_orders.id AND rn.voided = false) THEN 0 ELSE 1 END, date_received'))

csv_data = CSV.generate do |csv|
  csv << ['Customer Name', 'Order Number', 'Date Created', 'Date Released', 'Duration (Working Days)', 'Is Aerospace?']
  customer_orders.each do |order|
    release_notes = ReleaseNote.active.where(works_order_id: order.works_orders.pluck(:id)).order(:date)
    last_release_date = release_notes.maximum(:date)
    duration = last_release_date ? working_days_between(order.date_received, last_release_date) : nil
    is_aerospace = order.works_orders.any? { |wo| wo.part&.aerospace_defense? }
    csv << [order.customer.name, order.number, order.date_received.strftime('%d/%m/%Y'), last_release_date ? last_release_date.strftime('%d/%m/%Y') : '', duration || '', is_aerospace]
  end
end

puts csv_data

# Now generate the summary statistics
puts "\n"
puts "=" * 60
puts "PERFORMANCE ANALYSIS"
puts "=" * 60

# Parse the CSV data we just generated
rows = CSV.parse(csv_data, headers: true)
completed = rows.select { |r| r['Date Released'].present? && r['Duration (Working Days)'].present? }

aerospace_orders = completed.select { |r| r['Is Aerospace?'] == 'true' }
non_aerospace_orders = completed.select { |r| r['Is Aerospace?'] == 'false' }

aerospace_success = aerospace_orders.select { |r| r['Duration (Working Days)'].to_i <= 15 }
aerospace_failure = aerospace_orders.select { |r| r['Duration (Working Days)'].to_i > 15 }

non_aerospace_success = non_aerospace_orders.select { |r| r['Duration (Working Days)'].to_i <= 10 }
non_aerospace_failure = non_aerospace_orders.select { |r| r['Duration (Working Days)'].to_i > 10 }

total_success = aerospace_success.size + non_aerospace_success.size
total_failure = aerospace_failure.size + non_aerospace_failure.size

puts "\nDEADLINES:"
puts "  Non-Aerospace: 10 working days"
puts "  Aerospace:     15 working days"
puts "\n" + "=" * 60
puts "OVERALL RESULTS"
puts "=" * 60
puts "Total completed orders: #{completed.size}"
puts "Orders not yet released: #{rows.size - completed.size}"
puts ""
puts "Met deadline:    #{total_success} (#{'%.1f' % (total_success.to_f / completed.size * 100)}%)"
puts "Missed deadline: #{total_failure} (#{'%.1f' % (total_failure.to_f / completed.size * 100)}%)"

puts "\n" + "=" * 60
puts "NON-AEROSPACE ORDERS (<=10 days target)"
puts "=" * 60
puts "Total: #{non_aerospace_orders.size}"
puts "Met deadline:    #{non_aerospace_success.size} (#{'%.1f' % (non_aerospace_success.size.to_f / non_aerospace_orders.size * 100)}%)"
puts "Missed deadline: #{non_aerospace_failure.size} (#{'%.1f' % (non_aerospace_failure.size.to_f / non_aerospace_orders.size * 100)}%)"
if non_aerospace_orders.any?
  durations = non_aerospace_orders.map { |r| r['Duration (Working Days)'].to_i }
  puts "Average duration:   #{'%.1f' % (durations.sum.to_f / durations.size)} days"
  puts "Median duration:    #{durations.sort[durations.size / 2]} days"
  puts "Range:              #{durations.min}-#{durations.max} days"
end

puts "\n" + "=" * 60
puts "AEROSPACE ORDERS (<=15 days target)"
puts "=" * 60
puts "Total: #{aerospace_orders.size}"
puts "Met deadline:    #{aerospace_success.size} (#{'%.1f' % (aerospace_success.size.to_f / aerospace_orders.size * 100)}%)"
puts "Missed deadline: #{aerospace_failure.size} (#{'%.1f' % (aerospace_failure.size.to_f / aerospace_orders.size * 100)}%)"
if aerospace_orders.any?
  durations = aerospace_orders.map { |r| r['Duration (Working Days)'].to_i }
  puts "Average duration:   #{'%.1f' % (durations.sum.to_f / durations.size)} days"
  puts "Median duration:    #{durations.sort[durations.size / 2]} days"
  puts "Range:              #{durations.min}-#{durations.max} days"
end

# Show failures
all_failures = (aerospace_failure + non_aerospace_failure).sort_by { |r| -r['Duration (Working Days)'].to_i }
if all_failures.any?
  puts "\n" + "=" * 60
  puts "ORDERS THAT MISSED DEADLINE"
  puts "=" * 60
  all_failures.each do |row|
    deadline = row['Is Aerospace?'] == 'true' ? 15 : 10
    overage = row['Duration (Working Days)'].to_i - deadline
    aero_flag = row['Is Aerospace?'] == 'true' ? '[AERO]' : ''
    puts "%-40s %8s  %2d days (over by %d) %s" % [
      row['Customer Name'][0..39],
      row['Order Number'],
      row['Duration (Working Days)'].to_i,
      overage,
      aero_flag
    ]
  end
end

EOF
)" > october_orders.csv

<!-- HOW Find and Fix Lufthansa parts that don't require thickness measurements -->

customer = Organization.find_by("name ILIKE ?", "%lufthansa%")
puts "Customer: #{customer.name}"
puts "=" * 80

parts = Part.where(customer: customer, enabled: true)

actually_broken = []

parts.each do |part|
  next unless part.aerospace_defense?

  has_anodising = part.locked_operations.any? do |op|
    op_text = op["operation_text"]&.downcase || ""
    op_name = op["display_name"]&.downcase || ""
    op_text.include?("anodis") || op_name.include?("anodis")
  end

  next unless has_anodising

  wo = part.works_orders.last
  next unless wo

  rn = wo.release_notes.build
  unless rn.requires_thickness_measurements?
    actually_broken << part
  end
end

puts "Found #{actually_broken.count} parts that need fixing:\n"
actually_broken.each do |part|
  puts "  - #{part.display_name} (#{part.part_number})"
end

if actually_broken.empty?
  puts "✅ Nothing to fix!"
  exit
end

puts "\n" + "=" * 80
puts "Ready to fix these parts with chromic anodising treatment?"
puts "Type 'yes' to proceed:"
confirmation = gets.chomp

exit unless confirmation.downcase == 'yes'

puts "\nFixing parts..."
puts "=" * 80

actually_broken.each do |part|
  begin
    part.customisation_data["operation_selection"]["treatments"] = [
      {
        "type" => "chromic_anodising",
        "operation_id" => "CHROMIC_22V",
        "selected_jig_type" => "titanium_wire",
        "target_thickness" => 5
      }
    ].to_json

    part.save!

    # Verify the fix
    wo = part.works_orders.last
    rn = wo.release_notes.build
    requires = rn.requires_thickness_measurements?

    puts "✅ #{part.display_name} - Fixed! (requires_thickness: #{requires})"
  rescue => e
    puts "❌ #{part.display_name} - Failed: #{e.message}"
  end
end

puts "\n" + "=" * 80
puts "Done!"
