# db/seeds.rb
# Simple seed file for local testing the operational workflow

puts "🌱 Seeding database for local testing..."

# Create a test user first
user = User.find_or_create_by(email_address: "test@hardanodisingstl.com") do |u|
  u.username = "testuser"
  u.full_name = "Test User"
  u.password = "password123"
  u.enabled = true
end

puts "✅ Created user: #{user.display_name}"

# Create required sequences if they don't exist
sequences_to_create = [
  { key: 'release_note_number', starting_value: 1000 },
  { key: 'works_order_number', starting_value: 2000 },
  { key: 'invoice_number', starting_value: 3000 }
]

sequences_to_create.each do |seq_data|
  Sequence.find_or_create_by(key: seq_data[:key]) do |seq|
    seq.value = seq_data[:starting_value]
  end
  puts "✅ Created sequence: #{seq_data[:key]}"
end

# Create a test Xero contact first (required for organizations)
xero_contact = XeroContact.find_or_create_by(xero_id: "test-xero-contact-123") do |xc|
  xc.name = "Test Customer Ltd"
  xc.contact_status = "ACTIVE"
  xc.is_customer = true
  xc.is_supplier = false
  xc.accounts_receivable_tax_type = "OUTPUT2"
  xc.xero_data = {
    "email_address" => "test@testcustomer.com",
    "addresses" => [
      {
        "address_type" => "STREET",
        "address_line_1" => "123 Test Street",
        "city" => "Test City",
        "postal_code" => "TE5T 1NG"
      }
    ]
  }
  xc.last_synced_at = Time.current
end

puts "✅ Created Xero contact: #{xero_contact.name}"

# Create a test customer organization
customer = Organization.find_or_create_by(name: "Test Customer Ltd") do |org|
  org.xero_contact = xero_contact
  org.is_customer = true
  org.is_supplier = false
  org.enabled = true
end

puts "✅ Created customer: #{customer.name}"

# Create a simple part for the customer
part = Part.ensure(
  customer_id: customer.id,
  part_number: "WIDGET001",
  part_issue: "A"
)

puts "✅ Created part: #{part.display_name} for #{customer.name}"

# Create release level and transport method
release_level = ReleaseLevel.find_or_create_by(name: "Standard Release") do |rl|
  rl.statement = "The above parts have been processed in accordance with [SPECIFICATION] and are released for dispatch."
  rl.enabled = true
end

transport_method = TransportMethod.find_or_create_by(name: "Customer Collection") do |tm|
  tm.enabled = true
  tm.description = "Customer will collect parts from our facility"
end

puts "✅ Created release level: #{release_level.name}"
puts "✅ Created transport method: #{transport_method.name}"

# Create a basic Part Processing Instruction (PPI)
# First check if it already exists to avoid duplicates
existing_ppi = PartProcessingInstruction.find_by(
  part: part,
  customer: customer,
  part_number: "WIDGET001",
  part_issue: "A"
)

if existing_ppi
  puts "✅ PPI already exists: #{existing_ppi.specification}"
  ppi = existing_ppi
else
  # Create new PPI
  ppi = PartProcessingInstruction.create!(
    part: part,
    customer: customer,
    part_number: "WIDGET001",
    part_issue: "A",
    part_description: "Test Widget Component",
    specification: "Hard anodise to 25 microns, natural finish",
    process_type: "hard_anodising", # Use a valid process type from ProcessBuilder
    customisation_data: { "thickness" => "25 microns", "finish" => "Natural", "sealing" => "Sealed" },
    enabled: true
  )
  puts "✅ Created PPI: #{ppi.specification}"
end

# Create a second example part and PPI for testing
part2 = Part.ensure(
  customer_id: customer.id,
  part_number: "BRACKET200",
  part_issue: "B"
)

puts "✅ Created part: #{part2.display_name} for #{customer.name}"

existing_ppi2 = PartProcessingInstruction.find_by(
  part: part2,
  customer: customer,
  part_number: "BRACKET200",
  part_issue: "B"
)

if existing_ppi2
  puts "✅ PPI already exists: #{existing_ppi2.specification}"
  ppi2 = existing_ppi2
else
  ppi2 = PartProcessingInstruction.create!(
    part: part2,
    customer: customer,
    part_number: "BRACKET200",
    part_issue: "B",
    part_description: "Test Bracket Component",
    specification: "Anodise to 15 microns, black finish",
    process_type: "anodising",
    customisation_data: { "thickness" => "15 microns", "finish" => "Black", "sealing" => "Sealed" },
    enabled: true
  )
  puts "✅ Created PPI: #{ppi2.specification}"
end

puts "\n🎉 Seeding complete! You now have:"
puts "   - Customer: #{customer.name}"
puts "   - Parts: #{part.display_name}, #{part2.display_name}"
puts "   - PPIs: 2 processing instructions"
puts "   - User: #{user.display_name}"
puts "   - Release Level: #{release_level.name}"
puts "   - Transport Method: #{transport_method.name}"

puts "\n📋 You can now test the workflow:"
puts "   1. Create a Customer Order"
puts "   2. Create a Works Order from the Customer Order"
puts "   3. Create Release Notes from the Works Order"
puts "   4. Generate invoices from Release Notes"

puts "\n🔗 Start at: /customer_orders"

# Verify the setup worked
puts "\n🔍 Verification:"
parts_with_ppis = Part.enabled
                      .for_customer(customer)
                      .joins(:part_processing_instructions)
                      .where(part_processing_instructions: { customer: customer, enabled: true })
                      .distinct
                      .count

puts "   - Parts with PPIs for #{customer.name}: #{parts_with_ppis}"

if parts_with_ppis > 0
  puts "   ✅ Setup successful - works orders can be created!"
else
  puts "   ❌ Setup failed - no parts with PPIs found"
end
