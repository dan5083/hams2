# db/seeds/skipton_customer_mappings.rb
# This seed file creates SkiptonCustomerMapping records
# It includes both exact matches and corrected mismatches from the Xero→Skipton mapping audit

puts "🌱 Seeding Skipton Customer Mappings..."

mappings = [
  # EXACT MATCHES (84) - These work correctly already
  { xero_name: "C E Turner (Engineers) Limited", skipton_id: "TURNER" },
  { xero_name: "Seetru Ltd", skipton_id: "001164-001" },
  { xero_name: "Colin Mear Engineering Ltd", skipton_id: "003240-001" },
  { xero_name: "Sussex Community NHS Trust", skipton_id: "004315-001" },
  { xero_name: "Uvox Ltd", skipton_id: "008615-001" },
  { xero_name: "Sabit Limited", skipton_id: "020649-001" },
  { xero_name: "Renishaw plc", skipton_id: "021061-001" },
  { xero_name: "TEER COATINGS LTD", skipton_id: "026963-001" },
  { xero_name: "Engineering & Development Ltd", skipton_id: "049944-001" },
  { xero_name: "Kingston Engineering Co. Ltd", skipton_id: "050033-001" },
  { xero_name: "Transcal Engineering Ltd", skipton_id: "050047-001" },
  { xero_name: "Oilgear Towler Ltd", skipton_id: "050136-001" },
  { xero_name: "Grainger & Worrall Limited", skipton_id: "050151-001" },
  { xero_name: "Porvair Filtration Group Ltd", skipton_id: "050166-001" },
  { xero_name: "The Helping Hand Company", skipton_id: "050345-001" },
  { xero_name: "Lattimer Limited", skipton_id: "050384-001" },
  { xero_name: "Capital Aluminium Extrusions", skipton_id: "050601-001" },
  { xero_name: "Falcon Precision Engineering", skipton_id: "050750-001" },
  { xero_name: "McGeoch Technology Ltd", skipton_id: "050802-001" },
  { xero_name: "Sunlab Equipment", skipton_id: "050832-001" },
  { xero_name: "Vision Motorsport Eng Prod Ltd", skipton_id: "050919-001" },
  { xero_name: "LW Solutions Ltd", skipton_id: "050977-001" },
  { xero_name: "Market Metals Ltd", skipton_id: "059678-001" },
  { xero_name: "Cordelle Precisoin Engineering Ltd", skipton_id: "060011-001" },
  { xero_name: "Reaction Engines Ltd", skipton_id: "060460-001" },
  { xero_name: "Bay Engineering", skipton_id: "060556-001" },
  { xero_name: "R Winter Tooling", skipton_id: "060570-001" },
  { xero_name: "JFD Limited", skipton_id: "060865-001" },
  { xero_name: "Anthony Best Dynamics Ltd", skipton_id: "061079-001" },
  { xero_name: "SL Transportation Ltd", skipton_id: "061235-001" },
  { xero_name: "PCE Automation Ltd", skipton_id: "061412-001" },
  { xero_name: "M-Machine", skipton_id: "062790-001" },
  { xero_name: "Multimatic Motorsports Europe", skipton_id: "062908-001" },
  { xero_name: "Trueline Expanded Products Ltd", skipton_id: "062915-001" },
  { xero_name: "Freeman & Pardoe Ltd", skipton_id: "064534-001" },
  { xero_name: "Muller Redditch Ltd", skipton_id: "065110-001" },
  { xero_name: "TJW Precision", skipton_id: "065857-001" },
  { xero_name: "TJW Precision Engineering Ltd", skipton_id: "065863-001" },
  { xero_name: "CA Models Ltd", skipton_id: "065866-001" },
  { xero_name: "Monolution Limited", skipton_id: "066899-001" },
  { xero_name: "Exsel Design and Integration", skipton_id: "067463-001" },
  { xero_name: "Fox-Vps Ltd", skipton_id: "067953-001" },
  { xero_name: "Sumac Precision Engineering Ltd", skipton_id: "068940-001" },
  { xero_name: "RHH Franks Ltd", skipton_id: "069214-001" },
  { xero_name: "Singer Body & Paint Limited", skipton_id: "069260-001" },
  { xero_name: "Aluminium Droitwich", skipton_id: "069261-001" },
  { xero_name: "Foley Technologies Ltd", skipton_id: "069740-001" },
  { xero_name: "Simmatic Automation Specialist Ltd", skipton_id: "069744-001" },
  { xero_name: "XL Technical Services Ltd", skipton_id: "069847-001" },
  { xero_name: "Electroplating Contract Services Ltd", skipton_id: "069946-001" },
  { xero_name: "Ghillie Kettle Company", skipton_id: "070079-001" },
  { xero_name: "PDS (CNC) Engineering Ltd", skipton_id: "070899-001" },
  { xero_name: "Glassworks Hounsell Ltd", skipton_id: "070937-001" },
  { xero_name: "Wardtec Limited", skipton_id: "071112-001" },
  { xero_name: "Baker Engineering Ltd", skipton_id: "071205-001" },
  { xero_name: "Mussett Aerospace Ltd", skipton_id: "071249-001" },
  { xero_name: "Samuel Heath & Sons Plc", skipton_id: "071589-001" },
  { xero_name: "Nelson Tool Company (Stockport) Ltd", skipton_id: "071849-001" },
  { xero_name: "Pacegrade Limited", skipton_id: "072075-001" },
  { xero_name: "Machining Technology (Mach-Tech) Ltd", skipton_id: "072077-001" },
  { xero_name: "Beechwood Engineering Ltd", skipton_id: "072218-001" },
  { xero_name: "AMR GP Limited", skipton_id: "072453-001" },
  { xero_name: "Mechatronic Production Systems", skipton_id: "072730-001" },
  { xero_name: "Park Engineering Ltd", skipton_id: "073265-001" },
  { xero_name: "CloudNC", skipton_id: "073333-001" },
  { xero_name: "Geotek Ltd", skipton_id: "073432-001" },
  { xero_name: "Grainger & Worrall Machining Limited", skipton_id: "074051-001" },
  { xero_name: "BPM Engineering", skipton_id: "074171-001" },
  { xero_name: "Rola (Cylinder Manufacturers) Limited", skipton_id: "074460-001" },
  { xero_name: "Titan Motorsport & Automotive Engineerin", skipton_id: "074690-001" },
  { xero_name: "Heinrich Georg UK Ltd", skipton_id: "075440-001" },
  { xero_name: "Bowyer Engineering Ltd", skipton_id: "076659-001" },
  { xero_name: "XY Engineering Ltd", skipton_id: "076794-001" },
  { xero_name: "Servis Heat Treatment Co Ltd", skipton_id: "076872-001" },
  { xero_name: "Just Rollers Ltd", skipton_id: "077160-001" },
  { xero_name: "Alliance Development Group Ltd", skipton_id: "077306-001" },
  { xero_name: "Select Engineering (UK) Ltd", skipton_id: "077644-001" },
  { xero_name: "Driver Southall Ltd", skipton_id: "077709-001" },
  { xero_name: "LRP Engineering Ltd", skipton_id: "078872-001" },
  { xero_name: "Avant Manufacturing Ltd", skipton_id: "078963-001" },
  { xero_name: "Bluecore Heatsinks Limited", skipton_id: "079154-001" },
  { xero_name: "OTE Precision Engineering (UK) Ltd", skipton_id: "079488-001" },
  { xero_name: "Wicksteed Leisure Ltd", skipton_id: "079494-001" },

  # CORRECTED MISMATCHES - Fixed to use exact Xero names
  { xero_name: "Alcon Components", skipton_id: "083812-001" }, # was: Alcon Components Ltd
  { xero_name: "Arrayjet Ltd", skipton_id: "083822-001" }, # was: ARRAYJET
  { xero_name: "Bridgnorth Aluminium Limited", skipton_id: "1000000225" }, # was: Bridgnorth Aluminium Ltd
  { xero_name: "Brown & Hawthorne Ltd", skipton_id: "083834-001" }, # was: Brown & Hawthorne Limited
  { xero_name: "CAMERON BALLOONS LTD", skipton_id: "083839-001" }, # was: Cameron Balloons Ltd
  { xero_name: "Caterpillar Shrewsbury Limited", skipton_id: "083841-001" }, # was: Caterpillar Shrewsbury Ltd
  { xero_name: "Central Engineering Hydraulic Services Ltd", skipton_id: "083842-001" }, # was: Central Engineering Hydraulic Services L
  { xero_name: "Central Springs & Pressings Ltd", skipton_id: "083843-001" }, # was: Central Springs & Pressings Limited
  { xero_name: "Complete Fabrication Prototype & Production", skipton_id: "1000000224" }, # was: Complete Fabrication Modelmakers
  { xero_name: "Cross Manufacturing Company (1938) Ltd", skipton_id: "1000000212" }, # was: Cross Manufacturing Company (1938)
  { xero_name: "Cwm Engineering Ltd", skipton_id: "083854-001" }, # was: CWM Engineering Ltd (case difference)
  { xero_name: "DC Developments (Engineering) Ltd", skipton_id: "083859-001" }, # was: DC Developments (Engineering)
  { xero_name: "Dellner Percy Lane", skipton_id: "1000000031" }, # was: Dellner Percy Lane Products Ltd
  { xero_name: "Derry Precision Tools Ltd", skipton_id: "083860-001" }, # was: Derry Precision Tools
  { xero_name: "Dynatherm", skipton_id: "083865-001" }, # was: Dynatherm Ltd
  { xero_name: "GLASSWORKS HOUNSELL LTD", skipton_id: "1000000213" }, # was: Glassworks Hounsell Ltd (case)
  { xero_name: "Gainsborough Industrial Controls Ltd", skipton_id: "1000000128" }, # was: Gainsborough Industrial Controls
  { xero_name: "Glassworks Hounsell Limited", skipton_id: "1000000213" }, # was: Glassworks Hounsell Ltd
  { xero_name: "Global Single Source", skipton_id: "083886-001" }, # was: Global Single Source Ltd
  { xero_name: "Goldring Industries Ltd", skipton_id: "1000000093" }, # was: Goldring Industries Limited

  # MULTIPLE OPTIONS - Choose the best match:
  # Grainger & Worrall Ltd could be either:
  # - "Grainger & Worrall Limited" → 050151-001 (RECOMMENDED - parent company)
  # - "Grainger & Worrall Machining Limited" → 074051-001 (specific division)
  { xero_name: "Grainger & Worrall Ltd", skipton_id: "050151-001" }, # Using parent company ID

  { xero_name: "Heinrich Georg UK Limited", skipton_id: "075440-001" }, # was: Heinrich Georg UK Ltd
  { xero_name: "Helander Precision Engineering Ltd", skipton_id: "083890-001" }, # was: Helander Precision Engineering
  { xero_name: "JM Grail (General Engineers) Ltd", skipton_id: "1000000016" }, # was: JM Grail General Engineers Ltd

  # Kingston Engineering Co Ltd could be:
  # - "Kingston Engineering Co. Ltd" → 050033-001 (RECOMMENDED - just punctuation)
  { xero_name: "Kingston Engineering Co Ltd", skipton_id: "050033-001" },

  { xero_name: "Lymington Precision Engineering Co Ltd", skipton_id: "083920-001" }, # was: Lymington Precision Eng.Co Ltd
  { xero_name: "NCL Precision Engineering Ltd", skipton_id: "083942-001" }, # was: NCL (Precision Engineering)Ltd
  { xero_name: "Nova Racing Transmissions", skipton_id: "1000000230" }, # was: NOVA RACING TRANSMISSIONS (case)
  { xero_name: "OTM Servo Mechanism Limited", skipton_id: "083950-001" }, # was: OTM Servo Mechanism Ltd
  { xero_name: "Ocean Marine Systems", skipton_id: "083946-001" }, # was: Ocean Marine Systems Ltd
  { xero_name: "Parker Precision Limited", skipton_id: "083955-001" }, # was: Parker Precision Ltd
  { xero_name: "Preci-Spark Ltd", skipton_id: "083965-001" }, # was: Preci-Spark Limited
  { xero_name: "Precision Aerospace Component Engineering Ltd.", skipton_id: "083963-001" }, # was: Precision Aerospace Component
  { xero_name: "Precision Aluminium Casting & Engineering Ltd", skipton_id: "1000000080" }, # was: Precision Aluminium Casting & Eng Ltd
  { xero_name: "Renishaw PLC", skipton_id: "021061-001" }, # was: Renishaw plc (case)
  { xero_name: "Rodwell Engineering Group Ltd", skipton_id: "1000000025" }, # was: RODWELL ENGINEERING GROUP LTD (case)
  { xero_name: "Shanick Engineering Ltd", skipton_id: "1000000028" }, # was: Shanick Engineering
  { xero_name: "Sumac Precision Engineering", skipton_id: "068940-001" }, # was: Sumac Precision Engineering Ltd
  { xero_name: "Surefast Bolting Services Ltd", skipton_id: "097544-001" }, # was: Surefast Bolting Services Limited
  { xero_name: "Tarpey Harris T/A Altaras International Ltd", skipton_id: "084007-001" }, # was: Tarpey-Harris ltd t/a Altaras Int
  { xero_name: "Teer Coatings Ltd", skipton_id: "026963-001" }, # was: TEER COATINGS LTD (case)
  { xero_name: "Wilson & Sons (Engineering) Limited", skipton_id: "1000000152" }, # was: Wilson & Sons (Engineering) Ltd
  { xero_name: "Worcestershire Medal Services Ltd", skipton_id: "1000000169" }, # was: Worcestershire Medal Service Ltd
  { xero_name: "XCEL Aerospace Limited", skipton_id: "1000000077" }, # was: EL Aerospace Ltd (likely renamed)
]

# Create or update mappings
created_count = 0
updated_count = 0
skipped_count = 0

mappings.each do |mapping|
  record = SkiptonCustomerMapping.find_or_initialize_by(xero_name: mapping[:xero_name])

  if record.new_record?
    record.skipton_id = mapping[:skipton_id]
    if record.save
      created_count += 1
    else
      puts "❌ Failed to create: #{mapping[:xero_name]} - #{record.errors.full_messages.join(', ')}"
      skipped_count += 1
    end
  elsif record.skipton_id != mapping[:skipton_id]
    old_id = record.skipton_id
    record.skipton_id = mapping[:skipton_id]
    if record.save
      puts "📝 Updated: #{mapping[:xero_name]} (#{old_id} → #{mapping[:skipton_id]})"
      updated_count += 1
    else
      puts "❌ Failed to update: #{mapping[:xero_name]} - #{record.errors.full_messages.join(', ')}"
      skipped_count += 1
    end
  else
    skipped_count += 1
  end
end

puts ""
puts "✅ Seeding complete!"
puts "   Created: #{created_count}"
puts "   Updated: #{updated_count}"
puts "   Skipped: #{skipped_count} (already existed with same ID)"
puts ""
puts "⚠️  MANUAL ACTION REQUIRED:"
puts "   The following customers have invoices but no Skipton ID mapping yet:"
puts "   - 24 Locks (6 invoices)"
puts "   - A&M EDM Limited (2 invoices)"
puts "   - Aston Martin Aramco Cognizant Formula One (4 invoices)"
puts "   - Burcas Ltd (1 invoices)"
puts "   - Chelton Limited (1 invoices)"
puts "   - Cope Precision (4 invoices)"
puts "   - Curtiss-Wright Surface Technologies (1 invoices)"
puts "   - Hyde Details Limited (1 invoices)"
puts "   - Hydro Group UK Ltd (SAPA) (11 invoices)"
puts "   - Infinity CNC Ltd (1 invoices)"
puts "   - Lattimer Ltd (5 invoices)"
puts "   - NEWMAN LABELLING LTD. (1 invoices)"
puts "   - Newturn CNC Machining Ltd (2 invoices)"
puts "   - Red Bull Advanced Technologies Limited (2 invoices)"
puts "   - Ross Sport Europe Ltd (1 invoices)"
puts "   - Rotamic Engineering Limited (2 invoices)"
puts "   - Sesame Access Systems Ltd (2 invoices)"
puts "   - Surefasteners Limited (1 invoices)"
puts "   - TWG Cadillac Formula 1 Team Limited (1 invoices)"
puts "   - Thomas Tooling Ltd (1 invoices)"
puts "   - Torquemeters Ltd (1 invoices)"
puts "   - Unibloc Hygienic Technologies UK Ltd (1 invoices)"
puts "   - Walker AEC Ltd. (1 invoices)"
puts "   - Warman CNC Ltd (13 invoices)"
puts "   - Xenint Limited (1 invoices)"
puts ""
puts "   Add these to Skipton first, then add them to the mapping table."
