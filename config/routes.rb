Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/stripe" => "webhooks/stripe#create"

  resources :charges, only: %i[index show]
  resources :refunds, only: %i[index show new create] do
    member do
      post :replay     # demo: re-deliver the settlement webhook, prove exactly-once
      post :simulate   # demo: play Stripe's webhook (?outcome=succeeded|failed)
    end
  end
  resources :payouts, only: %i[index show new create] do
    member { post :simulate }   # demo: play Stripe's webhook (?outcome=paid|failed)
  end

  namespace :api do
    resources :refunds, only: %i[create show]
  end

  get "ledger" => "accounts#index", as: :ledger
  get "reconciliation" => "reconciliation#show", as: :reconciliation
  get "audit" => "audit#index", as: :audit
  get "health" => "health#show", as: :health

  root "refunds#index"
end
