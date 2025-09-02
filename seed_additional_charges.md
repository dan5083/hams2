# Additional Charge Presets Seed Data
# Run this in Heroku console after migration

additional_charge_presets_data = [
  # Fixed charges
  {
    name: "Freight 32 kg (next Day) DPD Local UK",
    description: "Large package freight charge for next day DPD delivery within UK",
    amount: 39.58,
    is_variable: false,
    calculation_type: nil
  },
  {
    name: "FAIR CHARGE",
    description: "Standard fair charge applied to orders",
    amount: 200.00,
    is_variable: false,
    calculation_type: nil
  },
  {
    name: "C OF C CHARGE",
    description: "Certificate of Conformity charge",
    amount: 20.00,
    is_variable: false,
    calculation_type: nil
  },
  {
    name: "Expedite £200",
    description: "Express processing charge",
    amount: 200.00,
    is_variable: false,
    calculation_type: nil
  },

  # Variable charges
  {
    name: "COST OF CHEMICALS",
    description: "Variable cost for chemical materials - updated per order",
    amount: 2778.60,
    is_variable: true,
    calculation_type: nil
  },
  {
    name: "COST OF CHEMICALS FOR STRIPPING ENP",
    description: "Chemical costs specifically for ENP stripping process",
    amount: nil,
    is_variable: true,
    calculation_type: nil
  },
  {
    name: "SMALL BARREL",
    description: "Small barrel processing charge",
    amount: nil,
    is_variable: true,
    calculation_type: nil
  },
  {
    name: "DIE FEED PIPE",
    description: "Die feed pipe processing charge",
    amount: nil,
    is_variable: true,
    calculation_type: nil
  },
  {
    name: "COLLECTION & DELIVERY CHARGES ASTL COLLECT",
    description: "Collection and delivery charges for ASTL",
    amount: nil,
    is_variable: true,
    calculation_type: nil
  },

  # Calculated shipping charges (weight-based)
  {
    name: "Next day DPD (up to 10 kg)",
    description: "Next day DPD delivery for packages up to 10kg",
    amount: 8.00,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 11 kg",
    description: "Next day DPD delivery for 11kg package",
    amount: 8.89,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 12 kg",
    description: "Next day DPD delivery for 12kg package",
    amount: 9.26,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next Day DPD 13 kg",
    description: "Next day DPD delivery for 13kg package",
    amount: 9.64,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 14 kg",
    description: "Next day DPD delivery for 14kg package",
    amount: 10.01,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 15 kg",
    description: "Next day DPD delivery for 15kg package",
    amount: 10.38,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 16 kg",
    description: "Next day DPD delivery for 16kg package",
    amount: 10.38,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 17 kg",
    description: "Next day DPD delivery for 17kg package",
    amount: 10.76,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 18 kg",
    description: "Next day DPD delivery for 18kg package",
    amount: 11.51,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 19 kg",
    description: "Next day DPD delivery for 19kg package",
    amount: 11.88,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 20 kg",
    description: "Next day DPD delivery for 20kg package",
    amount: 12.25,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 21 kg",
    description: "Next day DPD delivery for 21kg package",
    amount: 12.63,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 22 kg",
    description: "Next day DPD delivery for 22kg package",
    amount: 13.00,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 23 kg",
    description: "Next day DPD delivery for 23kg package",
    amount: 13.38,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 24 kg",
    description: "Next day DPD delivery for 24kg package",
    amount: 13.75,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 25 kg",
    description: "Next day DPD delivery for 25kg package",
    amount: 14.12,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 26 kg",
    description: "Next day DPD delivery for 26kg package",
    amount: 14.50,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 27 kg",
    description: "Next day DPD delivery for 27kg package",
    amount: 14.87,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 28 kg",
    description: "Next day DPD delivery for 28kg package",
    amount: 15.25,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 29 kg",
    description: "Next day DPD delivery for 29kg package",
    amount: 15.62,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },
  {
    name: "Next day DPD 30 kg",
    description: "Next day DPD delivery for 30kg package",
    amount: 15.99,
    is_variable: false,
    calculation_type: "weight_based_next_day"
  },

  # Premium 10:30 delivery charges
  {
    name: "by 10:30 DPD up to 10 kg",
    description: "Premium 10:30 DPD delivery for packages up to 10kg",
    amount: 19.48,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 11 kg",
    description: "Premium 10:30 DPD delivery for 11kg package",
    amount: 21.92,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 12 kg",
    description: "Premium 10:30 DPD delivery for 12kg package",
    amount: 22.42,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 13 kg",
    description: "Premium 10:30 DPD delivery for 13kg package",
    amount: 22.91,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 14 kg",
    description: "Premium 10:30 DPD delivery for 14kg package",
    amount: 23.41,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 15 kg",
    description: "Premium 10:30 DPD delivery for 15kg package",
    amount: 23.90,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 16 kg",
    description: "Premium 10:30 DPD delivery for 16kg package",
    amount: 24.40,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 17 kg",
    description: "Premium 10:30 DPD delivery for 17kg package",
    amount: 24.89,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 18 kg",
    description: "Premium 10:30 DPD delivery for 18kg package",
    amount: 25.39,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 19 kg",
    description: "Premium 10:30 DPD delivery for 19kg package",
    amount: 25.88,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 20 kg",
    description: "Premium 10:30 DPD delivery for 20kg package",
    amount: 26.38,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 21 kg",
    description: "Premium 10:30 DPD delivery for 21kg package",
    amount: 26.87,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 22 kg",
    description: "Premium 10:30 DPD delivery for 22kg package",
    amount: 27.37,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 23 kg",
    description: "Premium 10:30 DPD delivery for 23kg package",
    amount: 27.86,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 24 kg",
    description: "Premium 10:30 DPD delivery for 24kg package",
    amount: 28.36,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 25 kg",
    description: "Premium 10:30 DPD delivery for 25kg package",
    amount: 28.85,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 26 kg",
    description: "Premium 10:30 DPD delivery for 26kg package",
    amount: 29.35,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 27 kg",
    description: "Premium 10:30 DPD delivery for 27kg package",
    amount: 29.84,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 28 kg",
    description: "Premium 10:30 DPD delivery for 28kg package",
    amount: 30.34,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 29 kg",
    description: "Premium 10:30 DPD delivery for 29kg package",
    amount: 30.83,
    is_variable: false,
    calculation_type: "weight_based_premium"
  },
  {
    name: "by 10:30 DPD 30 kg",
    description: "Premium 10:30 DPD delivery for 30kg package",
    amount: 31.33,
    is_variable: false,
    calculation_type: "weight_based_premium"
  }
]

# Create all additional charge presets
created_count = 0
additional_charge_presets_data.each do |data|
  begin
    AdditionalChargePreset.create!(data)
    created_count += 1
    puts "Created: #{data[:name]} - £#{data[:amount] || 'Variable'}"
  rescue => e
    puts "Failed to create '#{data[:name]}': #{e.message}"
  end
end

puts "\nAdditional Charge Presets seed completed: #{created_count}/#{additional_charge_presets_data.length} created"
puts "Total additional charge presets in database: #{AdditionalChargePreset.count}"

# Summary by type
fixed_charges = AdditionalChargePreset.where(is_variable: false, calculation_type: nil).count
variable_charges = AdditionalChargePreset.where(is_variable: true).count
shipping_charges = AdditionalChargePreset.where.not(calculation_type: nil).count

puts "\nBreakdown:"
puts "- Fixed charges: #{fixed_charges}"
puts "- Variable charges: #{variable_charges}"
puts "- Calculated shipping charges: #{shipping_charges}"
