require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users

  # Queue dashboard: what is enqueued, retrying, or dead. Admins only -- Sidekiq::Web
  # exposes job arguments and lets you delete or replay jobs.
  # `authenticate` only sees the Warden user, which stays the admin while they are
  # viewing as someone else -- the constraint is what keeps the dashboard out of an
  # impersonated session.
  authenticate :user, ->(user) { user.admin? } do
    constraints ->(request) { request.session[Impersonation::IMPERSONATION_KEY].blank? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  end

  # The admin dashboard: site statistics, and the switches that change how the site
  # behaves. Admins only -- Admin::BaseController turns everyone else away.
  namespace :admin do
    resource :dashboard, only: %i[show update], controller: 'dashboard'
  end

  # Does this Letterboxd handle have a readable diary? Reachable signed out: the sign-up
  # form asks before the account exists.
  get '/letterboxd/check', to: 'letterboxd#check', as: :letterboxd_check

  # Pinged when somebody opens Letterboxd's review prompt, so their diary can be re-read
  # once the review has had time to appear in the feed.
  post '/letterboxd/reviewed', to: 'letterboxd#reviewed', as: :letterboxd_reviewed

  # User preferences
  patch '/users/toggle_dark_mode', to: 'users#toggle_dark_mode', as: :toggle_dark_mode

  # The account page behind the name in the navbar: what the user has, and the settings
  # that need no password to change. Email and password stay with Devise.
  resource :profile, only: %i[show update], controller: 'users'

  # Admins viewing the site as another user (see Impersonation)
  post '/impersonate/:id', to: 'impersonations#create', as: :impersonate_user
  delete '/impersonate', to: 'impersonations#destroy', as: :stop_impersonating

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
    get :entry_index
    # The entries of a channel nested in another, fetched when its row is opened rather
    # than shipped collapsed: one of these holds 215 cards.
    get :nested_entries
    post :top_entries
    post :add_season
    # Stepping through a channel's entries from its card inside another channel, the way
    # the arrows on a series card step through its episodes.
    patch :next_entry
    patch :previous_entry
    patch :toggle_default
    patch :move_to_list
    patch :subscribe
    patch :unsubscribe
    patch :mark_all_complete
    patch :mark_all_incomplete
    # Voting on what to watch: one page a room looks at together, reached by everyone else
    # from the QR code on it.
    resource :vote, only: [:show, :create], controller: 'votes' do
      post :cast
      post :close
      delete 'options/:option_id', action: :remove_option, as: :option
    end

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

end
