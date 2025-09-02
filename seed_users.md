# # Create hardcoded users for Hard Anodising Surface Treatments staff
# users_data = [
#   { email_address: "adrian@hardanodisingstl.com", full_name: "Adrian Bishop", username: "adrian.bishop" },
#   { email_address: "alan@hardanodisingstl.com", full_name: "Alan Vaughan", username: "alan.vaughan" },
#   { email_address: "ben@hardanodisingstl.com", full_name: "Ben Mcgowan", username: "ben.mcgowan" },
#   { email_address: "brian@hardanodisingstl.com", full_name: "Brian Benton", username: "brian.benton" },
#   { email_address: "chris@hardanodisingstl.com", full_name: "Chris Connon", username: "chris.connon" },
#   { email_address: "chris.bayliss@hardanodisingstl.com", full_name: "Chris Bayliss", username: "chris.bayliss" },
#   { email_address: "daniel@hardanodisingstl.com", full_name: "Daniel Bayliss", username: "daniel.bayliss" },
#   { email_address: "dave@hardanodisingstl.com", full_name: "Dave Bennett", username: "dave.bennett" },
#   { email_address: "elena@hardanodisingstl.com", full_name: "Elena Oprea", username: "elena.oprea" },
#   { email_address: "gary@hardanodisingstl.com", full_name: "Gary Rickets", username: "gary.rickets" },
#   { email_address: "gio@hardanodisingstl.com", full_name: "Gio Iacono", username: "gio.iacono" },
#   { email_address: "hams-2-app@hardanodisingstl.com", full_name: "HAMS Application Service", username: "hams.service" },
#   { email_address: "quality@hardanodisingstl.com", full_name: "Jim Ledger", username: "jim.ledger" },
#   { email_address: "judy@hardanodisingstl.com", full_name: "Judy Horton", username: "judy.horton" },
#   { email_address: "julia@hardanodisingstl.com", full_name: "Julia Chapman", username: "julia.chapman" },
#   { email_address: "nigel@hardanodisingstl.com", full_name: "Nigel Harrington", username: "nigel.harrington" },
#   { email_address: "phil@hardanodisingstl.com", full_name: "Phil Bayliss", username: "phil.bayliss" },
#   { email_address: "ross@hardanodisingstl.com", full_name: "Ross Wilson", username: "ross.wilson" },
#   { email_address: "sophie@hardanodisingstl.com", full_name: "Sophie Davis", username: "sophie.davis" },
#   { email_address: "tariq@hardanodisingstl.com", full_name: "Tariq Anwar", username: "tariq.anwar" },
#   { email_address: "careers@hardanodisingstl.com", full_name: "Tariq Anwar", username: "tariq.anwar.careers" }
# ]

# users_data.each do |user_data|
#   User.find_or_create_by(email_address: user_data[:email_address]) do |user|
#     user.full_name = user_data[:full_name]
#     user.username = user_data[:username]
#     user.password = SecureRandom.hex(16) # Random password since they use magic links
#     user.enabled = true
#   end
# end

# puts "Created #{users_data.count} users"
