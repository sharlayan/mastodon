# frozen_string_literal: true

namespace :api, format: false do
  namespace :v1 do
    resources :statuses, only: [] do
      scope module: :statuses do
        resources :reacted_by, controller: :reacted_by_accounts, only: :index
        post '/react/:id', to: 'reactions#create', constraints: { id: %r{[^/]+} }
        post '/unreact/:id', to: 'reactions#destroy', constraints: { id: %r{[^/]+} }
      end
    end
  end
end
