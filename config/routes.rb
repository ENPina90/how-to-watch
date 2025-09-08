Rails.application.routes.draw do
  devise_for :users
  root to: "lists#index"
  get 'test', to: 'pages#test'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  resources :lists do
    get :randomize
    get :watch_current
    get :top_entries
    patch :move_to_list
    resources :entries, only: [:new, :create]
  end
  resources :entries, only: [:show, :create, :edit, :update, :destroy] do
    member do
      get :complete
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
end
