Rails.application.routes.draw do
  root "pages#home"
  get "about", to: "pages#about", as: :about

  resource :session
  resource :registration, only: %i[new create]
  resource :account, only: %i[show update]
  resources :plans, only: :index
  resource :subscription, only: :create do
    post :manage
  end
  post "stripe/webhook", to: "stripe_webhooks#create", as: :stripe_webhook
  resources :passwords, param: :token

  resources :reports, only: %i[index new create show destroy] do
    get :photo, on: :member
  end
  resources :garage_cars, path: "garage" do
    resources :photos, only: %i[create destroy], controller: "garage_photos"
    resources :accessories, only: %i[create update destroy], controller: "garage_accessories" do
      resources :placements, only: %i[create update destroy], controller: "accessory_placements"
    end
  end
  # Our Garage
  get "community", to: "community#index", as: :community
  resources :forum_threads, path: "community/threads", only: :show do
    resources :posts, only: :create, controller: "forum_posts"
  end
  resources :forum_reports, path: "community/reports", only: :create
  get "community/:make", to: "community#make", as: :community_make
  get "community/:make/:model", to: "community#room", as: :community_room
  post "community/:make/:model/threads", to: "forum_threads#create", as: :community_room_threads

  get "r/:token", to: "shared_reports#show", as: :shared_report
  get "vehicle_lookup", to: "vehicle_lookups#show", as: :vehicle_lookup
  get "vehicle_lookup/models", to: "vehicle_lookups#models", as: :vehicle_models
  get "models", to: "model_profiles#show", as: :model_profile

  namespace :admin do
    root "dashboard#show"
    resources :users, only: :index do
      member do
        post :ban
        post :unban
      end
    end
    resources :reports, only: %i[index update]
    resources :errors, only: %i[index show update]
    resources :features, only: %i[index update], param: :key
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
