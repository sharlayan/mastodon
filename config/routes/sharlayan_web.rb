# frozen_string_literal: true

get '/nodeinfo/2.1', to: 'well_known/node_info#show_two_one', as: :nodeinfo_2_1_schema
get '/proxy/*any', to: 'misskey_compat/media_proxy#show', format: false
get 'user_custom.css', to: 'user_custom_css#show', as: :user_custom_css

get 'miauth/:session', to: 'miauth#show', as: :miauth
post 'miauth/:session', to: 'miauth#create'

constraints(username: %r{[^@/.]+}) do
  with_options to: 'accounts#show' do
    get '/@:username/clips'
    get '/@:username/pages'
    get '/@:username/pages/:name'
  end
end

get '/avatar/:acct', to: 'misskey_compat/avatars#show', constraints: { acct: %r{[^/]+} }, format: false, as: :misskey_compat_avatar
get '/url', to: 'misskey_compat/url_preview#show', as: :misskey_compat_url_preview
get '/scratchpad', to: 'misskey_compat/scratchpad#show', as: :scratchpad
post '/scratchpad', to: 'misskey_compat/scratchpad#run'
get '/notes/:id', to: 'misskey_compat/notes#show', constraints: { id: /[0-9a-z]+/ }, as: :misskey_compat_note

get '/drive_media/:id/(:style)', to: 'drive_media#show', as: :drive_media, format: false

namespace :multi_accounts do
  resource :entry, only: [:show], controller: :entries
  resource :callback, only: [:show], controller: :callbacks

  scope :auth, controller: :auth do
    get 'sign_in', action: :new, as: :auth_sign_in
    post 'sign_in', action: :create
    post 'verify_otp', action: :verify_otp, as: :auth_verify_otp
  end
end
