Rails.application.routes.draw do
  # Authentication routes
  resource :session
  resources :passwords, param: :token
  resources :registrations, only: [:new, :create]

  # Xero OAuth routes
  get '/auth/xero', to: 'xero_auth#authorize'
  get '/auth/xero/callback', to: 'xero_auth#callback'
  get '/test_xero_api', to: 'xero_auth#test_api'

  # 1. Parts management - Basic CRUD for parts
  resources :parts do
    member do
      patch :toggle_enabled
    end
    collection do
      get :search
    end
  end

  # Part Processing Instructions
  resources :part_processing_instructions, path: 'ppis' do
    member do
      patch :toggle_enabled
    end
    collection do
      get :search
    end
  end

  # 2. Customer Orders - Booking in orders
  resources :customer_orders do
    member do
      patch :void
    end

    # 3. Works Orders nested under customer orders for creation flow
    resources :works_orders, only: [:new, :create], shallow: true
  end

  # 3. Works Orders routes (main CRUD) - PDFs for shop floor route cards
  resources :works_orders do
    member do
      get :route_card       # Shop floor manufacturing instructions (HTML + PDF)
      # REMOVED: patch :complete - works orders now auto-complete
      patch :void
      patch :create_invoice # CHANGED: was book_out, now create_invoice
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
      # No PDF route - Xero handles invoice PDFs professionally
    end

    collection do
      get :new_manual       # For creating manual invoices
      post :create_manual
      post :create_from_release_notes # Bulk invoice creation
      post :push_selected_to_xero     # NEW: Bulk push selected invoices to Xero
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

  # API routes for AJAX functionality
  namespace :api do
    namespace :v1 do
      resources :parts, only: [:index, :show] do
        collection do
          get :search
        end
      end

      resources :ppis, only: [:index, :show] do
        collection do
          get :search
        end
      end

      resources :customer_orders, only: [:index, :show]
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
