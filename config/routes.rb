Rails.application.routes.draw do
  devise_for :users
  root to: "lists#index"
  get 'test', to: 'pages#test'

  # Health check endpoint for Railway
  get '/health', to: 'application#health'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  resources :lists do
    get :randomize
    get :watch_current
    get :top_entries
    patch :move_to_list
    patch :subscribe
    patch :unsubscribe
    resources :entries, only: [:new, :create]
  end
  resources :entries, only: [:show, :create, :edit, :update, :destroy] do
    member do
      get :complete
      patch :review
      patch :complete_without_review
      get :reportlink
      get :repair_image
      get :migrate_poster
      get :watch
      get :duplicate
      get :shuffle_current
      get :increment_current
      get :decrement_current
      patch :update_position
    end
  end

  # Letterboxd integration routes
  get '/letterboxd/connect', to: 'letterboxd#connect', as: :connect_letterboxd
  get '/letterboxd/callback', to: 'letterboxd#callback', as: :letterboxd_callback
  delete '/letterboxd/disconnect', to: 'letterboxd#disconnect', as: :disconnect_letterboxd
  post '/letterboxd/sync/:entry_id', to: 'letterboxd#sync_entry', as: :sync_entry_to_letterboxd
  post '/letterboxd/bulk_sync', to: 'letterboxd#bulk_sync', as: :bulk_sync_to_letterboxd
end
