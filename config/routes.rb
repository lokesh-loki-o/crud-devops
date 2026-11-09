Rails.application.routes.draw do
  # Health endpoint used by the Docker healthcheck and Kubernetes probes.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :tasks
    end
  end
end
