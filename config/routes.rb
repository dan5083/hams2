Rails.application.routes.draw do
  # Authentication routes
  resource :session
  resources :passwords, param: :token
  resources :registrations, only: [:new, :create]

  # Xero OAuth routes - MOVED BEFORE magic link route
  get '/auth/xero', to: 'xero_auth#authorize'
  get '/auth/xero/callback', to: 'xero_auth#callback'
  get '/test_xero_api', to: 'xero_auth#test_api'

  # Magic link route - MOVED AFTER Xero routes
  get '/auth/:token', to: 'sessions#magic_link', as: :magic_link

  # 1. Parts management - Now includes integrated processing instructions
  resources :parts do
    member do
      patch :toggle_enabled
      patch :lock_operations
      patch :update_locked_operations
    end
    collection do
      get :search
      # Operations endpoints for the complex treatment form
      post :filter_operations
      post :operation_details
      post :preview_operations
    end
  end

  # REMOVED: Part Processing Instructions routes - functionality merged into parts
  # Redirect old PPI routes to parts for any bookmarks/links
  get '/ppis', to: redirect('/parts')
  get '/ppis/new', to: redirect('/parts/new')
  get '/ppis/:id', to: redirect { |params, request| "/parts/#{params[:id]}" }
  get '/ppis/:id/edit', to: redirect { |params, request| "/parts/#{params[:id]}/edit" }

  # Legacy operations endpoints - redirect to parts
  post '/operations/filter', to: 'parts#filter_operations'
  post '/operations/details', to: 'parts#operation_details'
  post '/operations/preview_with_auto_ops', to: 'parts#preview_operations'

  # 2. Customer Orders - Booking in orders
  resources :customer_orders do
    member do
      patch :void
    end

    # 3. Works Orders nested under customer orders for creation flow
    resources :works_orders, only: [:new, :create], shallow: true
  end

  # 3. Works Orders routes (main CRUD) - Updated to reference parts directly
  resources :works_orders do
    member do
      get :route_card       # Shop floor manufacturing instructions (HTML + PDF)
      patch :void
      patch :create_invoice # Create invoice from works order
    end

    # 5. Release Notes nested under works orders
    resources :release_notes, except: [:index] do
      member do
        patch :void
        get :pdf            # Customer delivery/collection documentation
      end
    end
  end

  # 5. Release Notes (standalone routes for management) - PDFs for delivery docs
  resources :release_notes, only: [:index, :show, :edit, :update] do
    member do
      patch :void
      get :pdf              # Customer delivery/collection documentation
    end

    collection do
      get :pending_invoice  # Release notes ready for invoicing
    end
  end

  # 6. Invoice routes (PDFs handled by Xero)
  resources :invoices do
    member do
      patch :void
    end

    collection do
      get :new_manual       # For creating manual invoices
      post :create_manual
      post :create_from_release_notes # Bulk invoice creation
      post :push_selected_to_xero     # Bulk push selected invoices to Xero
    end

    # Invoice items for partial invoicing
    resources :invoice_items, except: [:index, :show]
  end

  # Xero invoice sync routes
  resources :xero_invoices, only: [] do
    member do
      post :push_single, path: 'push'
      post :sync_status
    end

    collection do
      post :push_batch, path: 'push_batch'
    end
  end

  # Reference data management routes
  resources :organizations, only: [:index, :show, :edit, :update] do
    collection do
      post :sync_from_xero
    end
  end

  resources :release_levels, except: [:show] do
    member do
      patch :toggle_enabled
    end
  end

  resources :transport_methods, except: [:show] do
    member do
      patch :toggle_enabled
    end
  end

  # Reporting and dashboard routes
  namespace :reports do
    get :works_orders
    get :release_notes
    get :invoicing
    get :customer_summary
  end

  # API routes for AJAX functionality - Updated to use parts
  namespace :api do
    namespace :v1 do
      resources :parts, only: [:index, :show] do
        collection do
          get :search
        end
      end

      # REMOVED: PPIs API routes - functionality moved to parts
      resources :customer_orders, only: [:index, :show]
    end
  end

  resources :specification_presets, except: [:show] do
    member do
      patch :toggle_enabled
    end
  end

  resources :additional_charge_presets, except: [:show] do
    member do
      patch :toggle_enabled
    end
  end

  # Health check route
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root route - Dashboard for authenticated users, login for unauthenticated
  root "dashboard#index"

  # Artifacts management
  get 'artifacts', to: 'artifacts#index'
end
