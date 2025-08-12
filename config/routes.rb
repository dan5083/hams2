Rails.application.routes.draw do
  # Authentication routes
  resource :session
  resources :passwords, param: :token
  resources :registrations, only: [:new, :create]

  # Xero OAuth routes
  get '/auth/xero', to: 'xero_auth#authorize'
  get '/auth/xero/callback', to: 'xero_auth#callback'
  get '/test_xero_api', to: 'xero_auth#test_api'

  # Invoice routes
  resources :invoices do
    member do
      post :void
    end

    collection do
      get :new_manual # For creating manual invoices
      post :create_manual
    end
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

  # Health check route
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes (commented out but available)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root route - Dashboard for authenticated users, login for unauthenticated
  root "dashboard#index"
end
