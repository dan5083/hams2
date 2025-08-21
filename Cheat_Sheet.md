# FYI to see decluttered tree use:
tree -I "node_modules|.git|.DS_Store|*.log|coverage|build|dist|tmp"
# Show all models with filenames as headers:
for file in app/models/[a-e]*.rb; do echo "=== $file ==="; cat "$file"; echo; done
for file in app/models/[f-j]*.rb; do echo "=== $file ==="; cat "$file"; echo; done
for file in app/models/[k-z]*.rb; do echo "=== $file ==="; cat "$file"; echo; done


# Show controllers.rb files starting with a-i
for file in app/controllers/[a-i]*.rb; do
  echo "=== $file ==="
  cat "$file"
  echo
done

# Show controllers.rb files starting with j-z
for file in app/controllers/[j-p]*.rb; do
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

# Routes & Schema
echo "=== db/schema.rb ==="; cat db/schema.rb; echo; echo "=== config/routes.rb ==="; cat config/routes.rb; echo

# Views
for f in app/views/artifacts/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/customer_orders/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/dashboard/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/layouts/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
for f in app/views/part_processing_instructions/*.html.erb; do echo "=== $f ==="; cat "$f"; echo; done
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


<!-- # See the helpers
for file in app/helpers/*.rb; do echo "=== $file ==="; cat "$file"; echo; done -->
<!-- # See the logic classes for recovery tracking
for file in app/logic/*.rb; do echo "=== $file ==="; cat "$file"; echo; done -->

<!-- # Show all js controllers with filenames as headers:
# JS Controllers [a-b]:
for file in app/javascript/controllers/**/[a-b]*_controller.js; do echo "=== $file ==="; cat "$file"; echo; done
# JS Controllers [c-i]:
for file in app/javascript/controllers/**/[c-i]*_controller.js; do echo "=== $file ==="; cat "$file"; echo; done
# JS Controllers [j-q]:

# JS Controllers [r–z]:
for f in app/javascript/controllers/**/[r-z]*_controller.js; do echo "=== $f ==="; cat "$f"; echo; done

# For all CSS files in stylesheets/Components A
for file in app/assets/stylesheets/components/[a]*.css; do echo "=== $file ==="; cat "$file"; echo; done
# For all CSS files in stylesheets/Components B
for file in app/assets/stylesheets/components/[b]*.css; do echo "=== $file ==="; cat "$file"; echo; done
# For all CSS files in stylesheets/Components C
for file in app/assets/stylesheets/components/[c]*.css; do echo "=== $file ==="; cat "$file"; echo; done
# For all CSS files in stylesheets/Components E–Z
for file in app/assets/stylesheets/components/[e-z]*.css; do echo "=== $file ==="; cat "$file"; echo; done -->
