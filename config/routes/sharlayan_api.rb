# frozen_string_literal: true

namespace :api, format: false do
  namespace :v1 do
    resources :statuses, only: [] do
      scope module: :statuses do
        resources :reacted_by, controller: :reacted_by_accounts, only: :index
        post '/react/:id', to: 'reactions#create', constraints: { id: %r{[^/]+} }
        post '/unreact/:id', to: 'reactions#destroy', constraints: { id: %r{[^/]+} }
        resources :clips, only: :index
      end
    end

    namespace :timelines do
      resources :antenna, only: :show
    end

    resources :favorite_emojis, only: [:index, :create, :destroy], param: :name
    resources :avatar_decorations, only: [:index]
    post '/avatar_decoration_mutes', to: 'avatar_decorations#create_mute', as: :avatar_decoration_mutes
    delete '/avatar_decoration_mutes/:id', to: 'avatar_decorations#destroy_mute', as: :avatar_decoration_mute
    resources :reaction_mutes, only: [:index, :create, :destroy]
    resources :custom_emoji_mutes, only: [:index, :create, :destroy] do
      collection do
        put :preferences
      end
    end
    resource :appearance, only: [:update], controller: :appearance

    resources :board_announcements, only: [:index, :show] do
      scope module: :board_announcements do
        resources :reactions, only: [:update, :destroy]
      end

      collection do
        get :unread_count
      end

      member do
        post :read
      end
    end

    resources :conversations, only: [] do
      collection do
        get 'with_account/:account_id', action: :with_account
        get 'with_status/:status_id', action: :with_status
      end

      member do
        get :statuses
      end
    end

    namespace :drive do
      resources :files, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :attach
          post :transfer_to_posts
          get :attached_notes
        end

        collection do
          get :find
          get :find_by_hash
          get :check_existence
          post :move_bulk
          post :upload_from_url
        end
      end
      resources :folders, only: [:index, :show, :create, :update, :destroy] do
        collection do
          get :find
        end
      end
      get :usage, to: 'usage#show'
      resource :settings, only: [:show, :update], controller: :settings
    end

    resources :reactions, only: [:index] do
      collection do
        get :summary
      end
    end

    resource :domain_mutes, only: [:show, :create, :destroy]

    resources :account_switches, only: [:index, :destroy] do
      collection do
        get :linked_unread_counts
        post :push_forward, action: :create_push_forward
        delete :push_forward, action: :destroy_push_forward
      end
      member do
        delete :inbound, action: :destroy_inbound
      end
    end

    resources :accounts, only: [] do
      scope module: :accounts do
        resources :circles, only: :index
        resources :clips, only: :index
        resources :pages, only: [:index, :show], param: :name
        resources :antennas, only: :index
        resources :exclude_antennas, only: :index
      end

      member do
        post :refetch
      end
    end

    resources :circles, only: [:index, :create, :show, :update, :destroy] do
      resource :accounts, only: [:show, :create, :destroy], module: :circles
      resources :statuses, only: [:index], module: :circles
    end

    resources :clips, only: [:index, :create, :show, :update, :destroy] do
      resources :statuses, only: [:index, :create, :destroy], module: :clips

      scope module: :clips do
        resource :favourite, only: :create, controller: :favourites
        post :unfavourite, to: 'favourites#destroy'
      end

      collection do
        get :favourites, to: 'clips/favourites#index'
      end
    end

    resources :pages, only: [:index, :create, :show, :update, :destroy] do
      member do
        post :like
        post :unlike
        post :main, action: :set_main
        delete :main, action: :unset_main
        post :series_main, action: :set_series_main
        delete :series_main, action: :unset_series_main
        post :unlock
      end

      collection do
        get :categories
        get :featured
      end
    end

    resources :page_series, only: [:index, :create, :update, :destroy]

    resources :antennas, only: [:index, :create, :show, :update, :destroy] do
      scope module: :antennas do
        resource :accounts, only: [:show, :create, :destroy]
        resource :exclude_accounts, only: [:show, :create, :destroy]
        resource :domains, only: [:show, :create, :destroy]
        resource :exclude_domains, only: [:show, :create, :destroy]
        resource :tags, only: [:show, :create, :destroy]
        resource :exclude_tags, only: [:show, :create, :destroy]
        resources :statuses, only: :destroy
      end
    end
  end

  namespace :web do
    resource :local_settings, only: [:show, :update]
  end

  namespace :misskey_compat, path: '' do
    post 'users/show', to: 'users#show'
    post 'get-avatar-decorations', to: 'avatar_decorations#index'

    post 'meta', to: 'meta#show'
    match 'endpoints', to: 'meta#endpoints', via: [:get, :post]
    match 'emojis', to: 'emojis#index', via: [:get, :post]
    match 'emoji', to: 'emojis#show', via: [:get, :post]
    match 'endpoint', to: 'meta#endpoint', via: [:get, :post]
    match 'get-online-users-count', to: 'meta#online_users_count', via: [:get, :post]
    match 'server-info', to: 'meta#server_info', via: [:get, :post]
    post 'stats', to: 'meta#stats'
    match 'charts/active-users', to: 'charts#active_users', via: [:get, :post]
    match 'charts/ap-request', to: 'charts#ap_request', via: [:get, :post]
    match 'charts/drive', to: 'charts#drive', via: [:get, :post]
    match 'charts/federation', to: 'charts#federation', via: [:get, :post]
    match 'charts/instance', to: 'charts#instance', via: [:get, :post]
    match 'charts/notes', to: 'charts#notes', via: [:get, :post]
    match 'charts/user/drive', to: 'charts#user_drive', via: [:get, :post]
    match 'charts/user/following', to: 'charts#user_following', via: [:get, :post]
    match 'charts/user/notes', to: 'charts#user_notes', via: [:get, :post]
    match 'charts/user/pv', to: 'charts#user_pv', via: [:get, :post]
    match 'charts/user/reactions', to: 'charts#user_reactions', via: [:get, :post]
    match 'charts/users', to: 'charts#users', via: [:get, :post]
    match 'federation/instances', to: 'federation#instances', via: [:get, :post]
    match 'federation/show-instance', to: 'federation#show_instance', via: [:get, :post]
    match 'federation/stats', to: 'federation#stats', via: [:get, :post]
    match 'federation/users', to: 'federation#users', via: [:get, :post]
    match 'federation/followers', to: 'federation#followers', via: [:get, :post]
    match 'federation/following', to: 'federation#following', via: [:get, :post]
    post 'federation/update-remote-user', to: 'federation#update_remote_user'
    post 'i', to: 'i#show'
    post 'i/update', to: 'i#update'
    post 'i/pin', to: 'i#pin'
    post 'i/unpin', to: 'i#unpin'
    post 'i/notifications', to: 'notifications#index'
    post 'i/notifications-grouped', to: 'notifications#index'
    post 'i/read-all-notifications', to: 'notifications#mark_all_as_read'
    post 'notifications/mark-all-as-read', to: 'notifications#mark_all_as_read'
    post 'notifications/create', to: 'notifications#create'

    post 'i/registry/get-all', to: 'registry#get_all'
    post 'i/registry/get', to: 'registry#get'
    post 'i/registry/get-detail', to: 'registry#get_detail'
    post 'i/registry/set', to: 'registry#set'
    post 'i/registry/remove', to: 'registry#remove'
    post 'i/registry/keys', to: 'registry#keys'
    post 'i/registry/keys-with-type', to: 'registry#keys_with_type'
    post 'i/registry/scopes-with-domain', to: 'registry#scopes_with_domain'
    post 'miauth/:session/check', to: 'miauth#check'
    post 'signin-flow', to: 'signin#create'

    post 'sw/register', to: 'sw#register'
    post 'sw/unregister', to: 'sw#unregister'
    post 'sw/show-registration', to: 'sw#show_registration'
    post 'sw/update-registration', to: 'stub#unsupported'

    post 'notes/timeline', to: 'notes#timeline'
    post 'notes/local-timeline', to: 'notes#local_timeline'
    post 'notes/hybrid-timeline', to: 'notes#hybrid_timeline'
    post 'notes/global-timeline', to: 'notes#global_timeline'
    post 'notes/show', to: 'notes#show'
    post 'notes/update', to: 'notes#update'
    post 'notes/scheduled/list', to: 'notes#scheduled_list'
    post 'notes/scheduled/cancel', to: 'notes#scheduled_cancel'
    post 'notes/drafts/list', to: 'notes#drafts_list'
    post 'notes/drafts/count', to: 'notes#drafts_count'
    post 'notes/drafts/create', to: 'notes#drafts_create'
    post 'notes/drafts/update', to: 'notes#drafts_update'
    post 'notes/drafts/delete', to: 'notes#drafts_delete'
    post 'notes/children', to: 'notes#children'
    post 'notes/replies', to: 'notes#replies'
    post 'notes/conversation', to: 'notes#conversation'
    post 'notes/renotes', to: 'notes#renotes'
    post 'notes/unrenote', to: 'notes#unrenote'
    post 'notes/state', to: 'notes#state'
    post 'notes/translate', to: 'notes#translate'
    post 'notes/reactions', to: 'notes#note_reactions'
    post 'notes/reactions/create', to: 'notes#reactions_create'
    post 'notes/reactions/delete', to: 'notes#reactions_delete'
    post 'notes/thread-muting/create', to: 'notes#thread_muting_create'
    post 'notes/thread-muting/delete', to: 'notes#thread_muting_delete'

    post 'drive/files/create', to: 'drive#create'
    post 'drive/files/attached-notes', to: 'drive#attached_notes'
    post 'drive', to: 'drive#unavailable'
    post 'drive/files', to: 'drive#index'
    post 'drive/files/show', to: 'drive#show'
    post 'drive/files/update', to: 'drive#update'
    post 'drive/files/delete', to: 'drive#destroy'
    post 'drive/files/find', to: 'drive#find'
    post 'drive/files/find-by-hash', to: 'drive#find_by_hash'
    post 'drive/files/check-existence', to: 'drive#check_existence'
    post 'drive/files/upload-from-url', to: 'drive#upload_from_url'
    post 'drive/files/move-bulk', to: 'drive#move_bulk'
    post 'drive/folders', to: 'drive_folders#index'
    post 'drive/folders/show', to: 'drive_folders#show'
    post 'drive/folders/create', to: 'drive_folders#create'
    post 'drive/folders/update', to: 'drive_folders#update'
    post 'drive/folders/delete', to: 'drive_folders#destroy'
    post 'drive/folders/find', to: 'drive_folders#find'

    post 'notes/create', to: 'notes#create'
    post 'notes/delete', to: 'notes#destroy'
    post 'notes/mentions', to: 'notes#mentions'
    post 'notes/featured', to: 'notes#featured'
    post 'notes/search', to: 'notes#search'
    post 'notes/search-by-tag', to: 'notes#search_by_tag'
    post 'notes/favorites/create', to: 'notes#favorites_create'
    post 'notes/favorites/delete', to: 'notes#favorites_delete'
    post 'notes/polls/vote', to: 'notes#polls_vote'
    post 'notes/polls/recommendation', to: 'notes#polls_recommendation'
    post 'i/favorites', to: 'notes#my_favorites'

    post 'ap/show', to: 'ap#show'
    post 'ap/get', to: 'ap#get'

    post 'roles/list', to: 'roles#index'
    post 'roles/show', to: 'roles#show'
    post 'roles/users', to: 'roles#users'
    post 'roles/notes', to: 'roles#notes'

    post 'users', to: 'accounts#index'
    post 'users/notes', to: 'accounts#notes'
    post 'users/reactions', to: 'accounts#reactions'
    post 'users/featured-notes', to: 'accounts#featured_notes'
    post 'users/search', to: 'accounts#search'
    post 'users/search-by-username-and-host', to: 'accounts#search_by_username_and_host'
    post 'users/followers', to: 'accounts#followers'
    post 'users/following', to: 'accounts#following'
    post 'users/report-abuse', to: 'accounts#report_abuse'
    post 'users/update-memo', to: 'accounts#update_memo'
    post 'pinned-users', to: 'accounts#pinned_users'

    post 'following/create', to: 'following#create'
    post 'following/update', to: 'following#update'
    post 'following/delete', to: 'following#destroy'
    post 'following/requests/list', to: 'following#requests'
    post 'following/requests/accept', to: 'following#accept_request'
    post 'following/requests/reject', to: 'following#reject_request'
    post 'following/requests/cancel', to: 'following#cancel_request'
    post 'following/invalidate', to: 'following#invalidate'
    post 'blocking/create', to: 'blocking#create'
    post 'blocking/delete', to: 'blocking#destroy'
    post 'blocking/list', to: 'blocking#index'
    post 'mute/list', to: 'mutes#index'
    post 'mute/create', to: 'mutes#create'
    post 'mute/delete', to: 'mutes#destroy'
    post 'renote-mute/list', to: 'mutes#renote_list'
    post 'renote-mute/create', to: 'mutes#renote_create'
    post 'renote-mute/delete', to: 'mutes#renote_destroy'

    match 'hashtags/trend', to: 'hashtags#trend', via: [:get, :post]
    post 'hashtags/list', to: 'hashtags#index'
    match 'hashtags/search', to: 'hashtags#search', via: [:get, :post]
    match 'hashtags/show', to: 'hashtags#show', via: [:get, :post]
    post 'hashtags/users', to: 'hashtags#users'

    post 'users/lists/list', to: 'lists#index'
    post 'users/lists/show', to: 'lists#show'
    post 'users/lists/create', to: 'lists#create'
    post 'users/lists/update', to: 'lists#update'
    post 'users/lists/delete', to: 'lists#destroy'
    post 'users/lists/push', to: 'lists#push'
    post 'users/lists/pull', to: 'lists#pull'
    post 'users/lists/get-memberships', to: 'lists#memberships'
    post 'users/lists/update-membership', to: 'lists#update_membership'
    post 'users/lists/create-from-public', to: 'lists#create_from_public'
    post 'notes/user-list-timeline', to: 'lists#timeline'

    post 'antennas/list', to: 'antennas#index'
    post 'antennas/show', to: 'antennas#show'
    post 'antennas/create', to: 'antennas#create'
    post 'antennas/update', to: 'antennas#update'
    post 'antennas/delete', to: 'antennas#destroy'
    post 'antennas/notes', to: 'antennas#notes'
    post 'antennas/remove-note', to: 'antennas#remove_note'

    post 'announcements', to: 'announcements#index'
    post 'announcements/show', to: 'announcements#show'
    post 'i/read-announcement', to: 'i#read_announcement'

    post 'clips/list', to: 'clips#index'
    post 'clips/show', to: 'clips#show'
    post 'clips/create', to: 'clips#create'
    post 'clips/update', to: 'clips#update'
    post 'clips/delete', to: 'clips#destroy'
    post 'clips/add-note', to: 'clips#add_note'
    post 'clips/remove-note', to: 'clips#remove_note'
    post 'clips/notes', to: 'clips#notes'
    post 'clips/favorite', to: 'clips#favorite'
    post 'clips/unfavorite', to: 'clips#unfavorite'
    post 'clips/my-favorites', to: 'clips#my_favorites'
    post 'users/clips', to: 'clips#by_user'
    post 'notes/clips', to: 'notes#clips'

    post 'pages/featured', to: 'pages#featured'
    post 'i/pages', to: 'pages#index'
    post 'i/page-likes', to: 'pages#likes'
    post 'users/pages', to: 'pages#by_user'
    post 'pages/show', to: 'pages#show'
    post 'pages/like', to: 'pages#like'
    post 'pages/unlike', to: 'pages#unlike'
    post 'pages/create', to: 'pages#create'
    post 'pages/update', to: 'pages#update'
    post 'pages/delete', to: 'pages#destroy'

    post 'chat/history', to: 'chat#empty'
    post 'chat/read-all', to: 'chat#noop'
    post 'chat/messages/user-timeline', to: 'chat#empty'
    post 'chat/messages/room-timeline', to: 'chat#empty'
    post 'chat/messages/show', to: 'chat#noop'
    post 'chat/messages/create-to-room', to: 'chat#noop'
    post 'chat/messages/create-to-user', to: 'chat#noop'
    post 'chat/messages/delete', to: 'stub#no_content'
    post 'chat/messages/react', to: 'stub#no_content'
    post 'chat/messages/search', to: 'chat#empty'
    post 'chat/messages/unreact', to: 'stub#no_content'
    post 'chat/rooms/create', to: 'chat#noop'
    post 'chat/rooms/owned', to: 'chat#empty'
    post 'chat/rooms/joining', to: 'chat#empty'
    post 'chat/rooms/members', to: 'chat#empty'
    post 'chat/rooms/show', to: 'chat#noop'
    post 'chat/rooms/update', to: 'chat#noop'
    post 'chat/rooms/delete', to: 'chat#noop'
    post 'chat/rooms/mute', to: 'chat#noop'
    post 'chat/rooms/leave', to: 'chat#noop'
    post 'chat/rooms/join', to: 'chat#noop'
    post 'chat/rooms/invitations/inbox', to: 'chat#empty'
    post 'chat/rooms/invitations/outbox', to: 'chat#empty'
    post 'chat/rooms/invitations/create', to: 'chat#noop'
    post 'chat/rooms/invitations/ignore', to: 'chat#noop'

    post 'flash/my', to: 'stub#unsupported'
    post 'flash/featured', to: 'stub#unsupported'
    post 'flash/search', to: 'stub#unsupported'
    post 'flash/my-likes', to: 'stub#unsupported'
    post 'flash/show', to: 'stub#unsupported'
    post 'flash/create', to: 'stub#unsupported'
    post 'flash/delete', to: 'stub#unsupported'
    post 'flash/update', to: 'stub#unsupported'
    post 'flash/like', to: 'stub#unsupported'
    post 'flash/unlike', to: 'stub#unsupported'
    post 'users/flashs', to: 'stub#unsupported'

    post 'gallery/posts', to: 'stub#unsupported'
    post 'gallery/featured', to: 'stub#unsupported'
    post 'gallery/popular', to: 'stub#unsupported'
    post 'i/gallery/posts', to: 'stub#unsupported'
    post 'i/gallery/likes', to: 'stub#unsupported'
    post 'users/gallery/posts', to: 'stub#unsupported'
    post 'gallery/posts/show', to: 'stub#unsupported'
    post 'gallery/posts/create', to: 'stub#unsupported'
    post 'gallery/posts/update', to: 'stub#unsupported'
    post 'gallery/posts/like', to: 'stub#unsupported'
    post 'gallery/posts/unlike', to: 'stub#unsupported'
    post 'gallery/posts/delete', to: 'stub#unsupported'

    post 'channels/followed', to: 'stub#unsupported'
    post 'channels/my-favorites', to: 'stub#unsupported'
    post 'channels/owned', to: 'stub#unsupported'
    post 'channels/featured', to: 'stub#unsupported'
    post 'channels/timeline', to: 'stub#unsupported'
    post 'channels/search', to: 'stub#unsupported'
    post 'channels/show', to: 'stub#unsupported'
    post 'channels/create', to: 'stub#unsupported'
    post 'channels/update', to: 'stub#unsupported'
    post 'channels/follow', to: 'stub#unsupported'
    post 'channels/unfollow', to: 'stub#unsupported'
    post 'channels/favorite', to: 'stub#unsupported'
    post 'channels/unfavorite', to: 'stub#unsupported'
    post 'channels/mute/create', to: 'stub#unsupported'
    post 'channels/mute/delete', to: 'stub#unsupported'
    post 'channels/mute/list', to: 'stub#unsupported'

    match 'admin/*any', to: 'stub#noop', via: [:get, :post], format: false
    post 'v2/admin/emoji/list', to: 'stub#noop'
    post 'app/create', to: 'stub#noop'
    post 'app/show', to: 'stub#noop'
    post 'bubble-game/ranking', to: 'stub#empty'
    post 'bubble-game/register', to: 'stub#no_content'
    post 'ping', to: 'stub#noop'
    post 'promo/read', to: 'stub#no_content'
    post 'request-reset-password', to: 'stub#unsupported'
    post 'reset-db', to: 'stub#unsupported'
    post 'reset-password', to: 'stub#unsupported'
    match 'retention', to: 'retention#index', via: [:get, :post]
    post 'reversi/cancel-match', to: 'stub#unsupported'
    post 'reversi/games', to: 'stub#unsupported'
    post 'reversi/invitations', to: 'stub#unsupported'
    post 'reversi/match', to: 'stub#unsupported'
    post 'reversi/show-game', to: 'stub#unsupported'
    post 'reversi/surrender', to: 'stub#unsupported'
    post 'reversi/verify', to: 'stub#unsupported'
    post 'i/change-password', to: 'stub#unsupported'
    post 'i/update-email', to: 'stub#unsupported'
    post 'i/export-antennas', to: 'stub#no_content'
    post 'i/export-blocking', to: 'stub#no_content'
    post 'i/export-clips', to: 'stub#no_content'
    post 'i/export-favorites', to: 'stub#no_content'
    post 'i/export-following', to: 'stub#no_content'
    post 'i/export-mute', to: 'stub#no_content'
    post 'i/export-notes', to: 'stub#no_content'
    post 'i/export-user-lists', to: 'stub#no_content'
    post 'i/import-antennas', to: 'stub#no_content'
    post 'i/import-blocking', to: 'stub#no_content'
    post 'i/import-following', to: 'stub#no_content'
    post 'i/import-muting', to: 'stub#no_content'
    post 'i/import-user-lists', to: 'stub#no_content'
    post 'i/claim-achievement', to: 'stub#no_content'
    match 'users/achievements', to: 'stub#empty', via: [:get, :post]
    post 'invite/create', to: 'stub#noop'
    post 'invite/delete', to: 'stub#no_content'
    match 'invite/list', to: 'stub#empty', via: [:get, :post]
    match 'invite/limit', to: 'stub#invite_limit', via: [:get, :post]
    match 'fetch-rss', to: 'stub#noop', via: [:get, :post]
    post 'fetch-external-resources', to: 'stub#noop'
    post 'test', to: 'stub#noop'
    post 'username/available', to: 'stub#unsupported'
    post 'verify-email', to: 'stub#unsupported'
  end
end
