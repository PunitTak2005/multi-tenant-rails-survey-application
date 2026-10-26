Rails.application.routes.draw do
  # Authenticated root
  root "dashboard#index"

  # Authentication
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # Dashboard
  get "/dashboard", to: "dashboard#index", as: :dashboard

  # Surveys & Submissions (Tenant scoped)
  resources :surveys do
    member do
      post :publish
    end
    resources :submissions, only: %i[index show]
  end

  # Tenant Analytics
  get "/analytics", to: "analytics#index", as: :analytics

  # Public Survey Flow (Unauthenticated)
  get "/s/:public_token", to: "public_surveys#show", as: :public_survey
  post "/s/:public_token", to: "public_surveys#submit", as: :submit_public_survey
  get "/s/:public_token/success", to: "public_surveys#success", as: :public_survey_success

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
