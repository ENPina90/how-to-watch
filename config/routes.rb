require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: 'users/registrations' }

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
    resource :dashboard, only: %i[show update], controller: 'dashboard' do
      # Moves every channel onto one provider. POST rather than PATCH on the dashboard
      # itself: it rewrites rows across two tables and has nothing to do with the settings
      # row that `update` edits.
      post :reset_source
      # The two sweeps, on demand. POST because they enqueue work; they are the same jobs
      # the weekly schedule runs, so there is one implementation and one set of results.
      post :run_poster_scan
      post :run_embed_scan
    end

    # The adverts that fill the gap between programmes on /cable. Admin-only and nowhere
    # else in the app, so they live under /admin rather than beside /sources.
    resources :commercial_reels, except: :show do
      member do
        # What it looks like when it comes up in a break -- the same embed, at the same
        # sort of offset. A GET because it only plays something.
        get :preview
        # Reads the runtime off YouTube. PATCH because it writes one.
        patch :fetch_duration
      end
    end
  end

  # Does this Letterboxd handle have a readable diary? Reachable signed out: the sign-up
  # form asks before the account exists.
  get '/letterboxd/check', to: 'letterboxd#check', as: :letterboxd_check

  # The Letterboxd button. Bounces through the app so the film's canonical slug can be
  # resolved -- only /film/<slug>/review/ opens the review prompt -- and so a diary
  # refresh can be booked for once the review has had time to reach the feed.
  # entry_id is optional: watch_now plays a film the app has no Entry for, and names it
  # by imdb/tmdb id instead.
  get '/letterboxd/review(/:entry_id)', to: 'letterboxd#review', as: :letterboxd_review

  # Run the diary sync by hand, for when the queue has not.
  post '/letterboxd/sync', to: 'letterboxd#sync', as: :letterboxd_sync

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

  # Cable: channels that are already running when you turn them on. The channel is in the
  # path rather than a query parameter because it is the whole address here -- there is no
  # entry to name, since what is playing is whatever the schedule says at this second.
  # Both are GETs and neither writes: /cable records nothing about the viewer.
  get 'cable', to: 'cable#show', as: :cable
  # Before the :id route, and it has to stay there -- "guide" would otherwise be read as a
  # channel id, cast to nothing, and quietly serve channel one.
  get 'cable/guide', to: 'cable#guide', as: :cable_guide
  # The one thing under /cable that writes anything, which is why it is the one POST.
  # Admin only, and it rewrites today for every channel at once.
  post 'cable/regenerate', to: 'cable#regenerate', as: :cable_regenerate
  get 'cable/:id', to: 'cable#show', as: :cable_channel

  # The phone view or the full one, by the viewer's own say-so rather than by what their
  # user agent implies. A POST because it changes what every page after it renders.
  post '/view_mode', to: 'application#view_mode', as: :view_mode

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
    patch :toggle_favorite
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

  # Watch parties. The token is the invitation, so it addresses the room rather than an
  # id -- `show` is the join link people paste to each other.
  resources :watch_parties, only: %i[show create destroy], param: :token

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
      # File a copy in the member's own favourites channel, or take it out again. A write,
      # and per-user rather than shared -- it touches nobody's copy but their own.
      post :favorite
      delete :favorite, action: :unfavorite
      patch :shuffle_current
      patch :increment_current
      patch :decrement_current
      patch :update_position
      patch :set_source
      patch :update_poster
      # POST rather than PATCH because navigator.sendBeacon -- how the position is saved
      # as the page goes away -- can only send POST.
      post :progress
      # What the player says the file actually runs to. A correction to the catalogue, so a
      # write, so not a GET.
      patch :runtime
      # Reads stay GET: `watch` renders the player page and `fetch_posters` is a lookup.
      get :watch
      get :fetch_posters
    end
  end

  # What the app has to tell you. Admin-only kinds are filtered per notification rather
  # than per page, so this stays everyone's as more kinds arrive.
  resources :notifications, only: :index do
    member { patch :dismiss }
    collection { patch :dismiss_all }
  end

  # Streaming source/provider definitions (managed via modals on the watch page, and from
  # the index at /sources)
  resources :sources, only: [:index, :create, :update, :destroy] do
    # The order admins drag them into, which is also the order the app falls back through.
    collection { patch :reorder }

    member do
      # Both change how the app plays things, so neither is a GET.
      patch :renew
      patch :deactivate
      # Plays a known title through this provider and nothing else, to answer "is this
      # domain still alive" without hunting for an entry that uses it.
      get :test
    end
  end

end
