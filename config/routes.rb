Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/stripe" => "webhooks/stripe#create"

  resources :charges, only: %i[index show]
  resources :refunds, only: %i[index show new create] do
    member { post :replay }   # demo: re-deliver the settlement webhook, prove exactly-once
  end
  resources :payouts, only: %i[index show new create]

  namespace :api do
    resources :refunds, only: %i[create show]
  end

  get "ledger" => "accounts#index", as: :ledger
  get "reconciliation" => "reconciliation#show", as: :reconciliation
  get "audit" => "audit#index", as: :audit
  get "health" => "health#show", as: :health

  root "refunds#index"
end
