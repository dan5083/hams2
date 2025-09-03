# FYI to see decluttered tree use:
tree -I "node_modules|.git|.DS_Store|*.log|coverage|build|dist|tmp"
# Show all models with filenames as headers:
for file in app/models/[a-e]*.rb; do echo "=== $file ==="; cat "$file"; echo; done
for file in app/models/[f-j]*.rb; do echo "=== $file ==="; cat "$file"; echo; done
for file in app/models/[k-p]*.rb; do echo "=== $file ==="; cat "$file"; echo; done
for file in app/models/[q-z]*.rb; do echo "=== $file ==="; cat "$file"; echo; done

# Show controllers.rb files starting with a-i
for file in app/controllers/[a-e]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show controllers.rb files starting with j-z
for file in app/controllers/[f-j]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show controllers.rb files starting with j-z
for file in app/controllers/[k-p]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show controllers.rb files starting with j-z
for file in app/controllers/[q-z]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Remember config/initializers/operation_library.rb

# Routes & Schema
echo "=== db/schema.rb ==="; cat db/schema.rb; echo; echo "=== config/routes.rb ==="; cat config/routes.rb; echo

# Show operation library base file
echo "=== app/operation_library/operation.rb ==="
cat "app/operation_library/operation.rb"
echo

# Op files a-g
for file in app/operation_library/operations/[a-g]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show hard_anodising specifically
echo "=== app/operation_library/operations/hard_anodising.rb ==="
cat "app/operation_library/operations/hard_anodising.rb"
echo

# Show operations i-p
for file in app/operation_library/operations/[i-p]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show operations q-z
for file in app/operation_library/operations/[q-z]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Views
for f in app/views/artifacts/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/customer_orders/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/dashboard/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/layouts/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done

for f in app/views/parts/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done

for f in app/views/passwords/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/passwords_mailer/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/registrations/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/release_levels/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/release_notes/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/sessions/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/shared/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/transport_methods/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/works_orders/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/xero_auth/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done


<!-- HOW TO SEQUENCE FROM 1 -->

# Step 1: Start the console
heroku console

# Step 2: Clear the data (in the console) Clear dependent records first, then independent ones
InvoiceItem.delete_all
Invoice.delete_all
ReleaseNote.delete_all
WorksOrder.delete_all
CustomerOrder.delete_all
Part.delete_all
Sequence.delete_all

puts "All records cleared"

# Step 3: Create sequences (still in console) Create the required sequences
['works_order_number', 'release_note_number', 'invoice_number', 'customer_order_number'].each do |key|
  seq = Sequence.create!(key: key, value: 1)
  puts "Created sequence: #{key} = #{seq.value}"
end
