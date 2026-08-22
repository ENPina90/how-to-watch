require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users

  # Queue dashboard: what is enqueued, retrying, or dead. Admins only -- Sidekiq::Web
  # exposes job arguments and lets you delete or replay jobs.
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end

  # User preferences
  patch '/users/toggle_dark_mode', to: 'users#toggle_dark_mode', as: :toggle_dark_mode

  root to: "lists#index"
  get 'watch_now', to: 'pages#watch_now'

  # Health check endpoint for Railway
  get '/health', to: 'application#health'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  resources :lists do
    collection do
      get :search
    end
    get :watch_current
    post :top_entries
    post :add_season
    patch :move_to_list
    patch :subscribe
    patch :unsubscribe
    patch :mark_all_complete
    patch :mark_all_incomplete
    resources :entries, only: [:new, :create]
  end

  # Add to favorites route (not nested under lists)
  post '/lists/add_to_favorites', to: 'lists#add_to_favorites'
  # Add to list route (not nested under lists)
  post '/lists/add_to_list', to: 'lists#add_to_list'
  resources :entries, only: [:show, :create, :edit, :update, :destroy] do
    member do
      # Anything that writes is a non-GET verb: CSRF tokens do not protect GET, so a
      # prefetch, a crawler, or an <img src> pointing here could otherwise change state.
      patch :complete
      patch :review
      patch :complete_without_review
      patch :reportlink
      patch :repair_image
      patch :migrate_poster
      post :duplicate
      patch :shuffle_current
      patch :increment_current
      patch :decrement_current
      patch :update_position
      patch :set_source
      patch :update_poster
      # Reads stay GET: `watch` renders the player page and `fetch_posters` is a lookup.
      get :watch
      get :fetch_posters
    end
  end

  # Streaming source/provider definitions (managed via modals on the watch page)
  resources :sources, only: [:index, :create, :update, :destroy]

  # Letterboxd integration routes
  get '/letterboxd/connect', to: 'letterboxd#connect', as: :connect_letterboxd
  get '/letterboxd/callback', to: 'letterboxd#callback', as: :letterboxd_callback
  delete '/letterboxd/disconnect', to: 'letterboxd#disconnect', as: :disconnect_letterboxd
  post '/letterboxd/sync/:entry_id', to: 'letterboxd#sync_entry', as: :sync_entry_to_letterboxd
  post '/letterboxd/bulk_sync', to: 'letterboxd#bulk_sync', as: :bulk_sync_to_letterboxd
end
