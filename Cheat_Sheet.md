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

october_start = Date.new(2025, 10, 1) <!-- edit -->
october_end = Date.new(2025, 10, 31) <!-- edit -->

customer_orders = CustomerOrder.includes(:customer, works_orders: :release_notes)
                                .where(voided: false)
                                .where(date_received: october_start..october_end)
                                .order(Arel.sql('CASE WHEN EXISTS (SELECT 1 FROM works_orders wo JOIN release_notes rn ON rn.works_order_id = wo.id WHERE wo.customer_order_id = customer_orders.id AND rn.voided = false) THEN 0 ELSE 1 END, date_received'))

CSV.generate do |csv|
  csv << ['Customer Name', 'Order Number', 'Date Created', 'Date Released', 'Duration (Working Days)']
  customer_orders.each do |order|
    release_notes = ReleaseNote.active.where(works_order_id: order.works_orders.pluck(:id)).order(:date)
    last_release_date = release_notes.maximum(:date)
    duration = last_release_date ? working_days_between(order.date_received, last_release_date) : nil
    csv << [order.customer.name, order.number, order.date_received.strftime('%d/%m/%Y'), last_release_date ? last_release_date.strftime('%d/%m/%Y') : '', duration || '']
  end
end
EOF
)" > october_orders.csv
