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
    resources :entries, only: [:new, :create]
  end
  resources :entries, only: [:show, :edit, :update, :destroy] do
    member do
      get :complete
      get :reportlink
      get :watch
      get :duplicate
      get :increment_current
      get :decrement_current
    end
  end
end
