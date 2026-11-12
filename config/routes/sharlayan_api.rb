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
      resource :rp_hidden, only: :show, controller: :rp_hidden
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
    resource :inline_compose_tabs, only: [:update], controller: :inline_compose_tabs
    resource :federation_universe, only: :show

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

    namespace :chat do
      resource :settings, only: [:show, :update], controller: :settings
      resources :conversations, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :read
          delete :leave
          delete 'members/:account_id', action: :kick
          post :mute
          post :unmute
          post :archive
          post :unarchive
        end

        resources :messages, only: [:index, :create]
        resources :invitations, only: :create

        resource :voice, only: :show, controller: :voice_calls do
          post :join
          post :status
          post :kick
          post :mute
        end
      end

      get :voice_states, to: 'voice_calls#index'

      resources :messages, only: [:show, :update, :destroy] do
        collection do
          get :search
        end
      end
      post 'messages/:message_id/reactions', to: 'reactions#create'
      delete 'messages/:message_id/reactions/:reaction', to: 'reactions#destroy', constraints: { reaction: %r{[^/]+} }

      resources :invitations, only: [:index, :destroy] do
        member do
          post :accept
          post :reject
        end
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
        resources :page_series, only: :index
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
        get :statistics
      end
    end

    resources :page_series, only: [:index, :create, :update, :destroy] do
      collection do
        get :others
      end
    end

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
    post 'users/relation', to: 'users#relation'
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
    post 'notifications/flush', to: 'notifications#flush'
    post 'notifications/test-notification', to: 'notifications#test_notification'

    post 'i/registry/get-all', to: 'registry#get_all'
    post 'i/registry/get', to: 'registry#get'
    post 'i/registry/get-detail', to: 'registry#get_detail'
    post 'i/registry/set', to: 'registry#set'
    post 'i/registry/remove', to: 'registry#remove'
    post 'i/registry/keys', to: 'registry#keys'
    post 'i/registry/keys-with-type', to: 'registry#keys_with_type'
    post 'i/registry/scopes-with-domain', to: 'registry#scopes_with_domain'
    post 'i/webhooks/list', to: 'webhooks#index'
    post 'i/webhooks/show', to: 'webhooks#show'
    post 'i/webhooks/create', to: 'webhooks#create'
    post 'i/webhooks/update', to: 'webhooks#update'
    post 'i/webhooks/delete', to: 'webhooks#destroy'
    post 'i/webhooks/test', to: 'webhooks#test'
    post 'i/2fa/register', to: 'two_factor#register'
    post 'i/2fa/done', to: 'two_factor#done'
    post 'i/2fa/unregister', to: 'two_factor#unregister'
    post 'i/2fa/register-key', to: 'two_factor#register_key'
    post 'i/2fa/key-done', to: 'two_factor#key_done'
    post 'i/2fa/remove-key', to: 'two_factor#remove_key'
    post 'i/2fa/update-key', to: 'two_factor#update_key'
    post 'i/2fa/password-less', to: 'stub#unsupported'
    post 'i/signin-history', to: 'signin_history#index'
    post 'my/apps', to: 'apps#index'
    post 'i/apps', to: 'tokens#index'
    post 'i/authorized-apps', to: 'tokens#authorized_apps'
    post 'i/revoke-token', to: 'tokens#revoke'
    post 'i/regenerate-token', to: 'tokens#regenerate'
    post 'miauth/gen-token', to: 'tokens#gen_token'
    post 'auth/session/generate', to: 'auth_sessions#generate'
    post 'auth/session/show', to: 'auth_sessions#show'
    post 'auth/session/userkey', to: 'auth_sessions#userkey'
    post 'auth/accept', to: 'auth_sessions#accept'
    post 'miauth/:session/check', to: 'miauth#check'
    post 'signin-flow', to: 'signin#create'

    post 'sw/register', to: 'sw#register'
    post 'sw/unregister', to: 'sw#unregister'
    post 'sw/show-registration', to: 'sw#show_registration'
    post 'sw/update-registration', to: 'sw#update_registration'

    post 'notes', to: 'notes#index'
    post 'notes/timeline', to: 'notes#timeline'
    post 'notes/local-timeline', to: 'notes#local_timeline'
    post 'notes/hybrid-timeline', to: 'notes#hybrid_timeline'
    post 'notes/global-timeline', to: 'notes#global_timeline'
    post 'notes/show', to: 'notes#show'
    post 'notes/show-partial-bulk', to: 'notes#show_partial_bulk'
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
    post 'drive/files/attached-chat-messages', to: 'drive#attached_chat_messages'
    post 'drive', to: 'drive#overview'
    post 'drive/stream', to: 'drive#stream'
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
    post 'users/get-frequently-replied-users', to: 'accounts#frequently_replied_users'
    post 'users/get-following-users-by-birthday', to: 'birthdays#index'
    post 'users/recommendation', to: 'accounts#recommendation'
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
    post 'following/list', to: 'following#index'
    post 'following/update-all', to: 'following#update_all'
    post 'following/requests/list', to: 'following#requests'
    post 'following/requests/sent', to: 'following#sent_requests'
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
    post 'users/lists/favorite', to: 'lists#favorite'
    post 'users/lists/unfavorite', to: 'lists#unfavorite'
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

    post 'chat/history', to: 'chat#history'
    post 'chat/read-all', to: 'chat#read_all'
    post 'chat/messages/user-timeline', to: 'chat#user_timeline'
    post 'chat/messages/room-timeline', to: 'chat#room_timeline'
    post 'chat/messages/show', to: 'chat#show'
    post 'chat/messages/create-to-room', to: 'chat#create_to_room'
    post 'chat/messages/create-to-user', to: 'chat#create_to_user'
    post 'chat/messages/update', to: 'chat#update'
    post 'chat/messages/delete', to: 'chat#destroy'
    post 'chat/messages/react', to: 'chat#react'
    post 'chat/messages/search', to: 'chat#search'
    post 'chat/messages/unreact', to: 'chat#unreact'
    post 'chat/rooms/create', to: 'chat#create_room'
    post 'chat/rooms/owned', to: 'chat#owned_rooms'
    post 'chat/rooms/joining', to: 'chat#joining_rooms'
    post 'chat/rooms/members', to: 'chat#room_members'
    post 'chat/rooms/show', to: 'chat#show_room'
    post 'chat/rooms/update', to: 'chat#update_room'
    post 'chat/rooms/delete', to: 'chat#destroy_room'
    post 'chat/rooms/mute', to: 'chat#mute_room'
    post 'chat/rooms/leave', to: 'chat#leave_room'
    post 'chat/rooms/kick', to: 'chat#kick_member'
    post 'chat/rooms/join', to: 'chat#join_room'
    post 'chat/rooms/invitations/inbox', to: 'chat#invitations_inbox'
    post 'chat/rooms/invitations/outbox', to: 'chat#invitations_outbox'
    post 'chat/rooms/invitations/create', to: 'chat#create_invitation'
    post 'chat/rooms/invitations/ignore', to: 'chat#ignore_invitation'
    post 'chat/rooms/invitations/reject', to: 'chat#reject_invitation'
    post 'chat/rooms/invitations/cancel', to: 'chat#cancel_invitation'

    post 'flash/my', to: 'flash#mine'
    post 'flash/featured', to: 'flash#featured'
    post 'flash/search', to: 'flash#search'
    post 'flash/my-likes', to: 'flash#likes'
    post 'flash/show', to: 'flash#show'
    post 'flash/create', to: 'flash#create'
    post 'flash/delete', to: 'flash#destroy'
    post 'flash/update', to: 'flash#update'
    post 'flash/like', to: 'flash#like'
    post 'flash/unlike', to: 'flash#unlike'
    post 'users/flashs', to: 'flash#by_user'

    post 'gallery/posts', to: 'gallery#index'
    post 'gallery/featured', to: 'gallery#featured'
    post 'gallery/popular', to: 'gallery#popular'
    post 'i/gallery/posts', to: 'gallery#mine'
    post 'i/gallery/likes', to: 'gallery#likes'
    post 'users/gallery/posts', to: 'gallery#by_user'
    post 'gallery/posts/show', to: 'gallery#show'
    post 'gallery/posts/create', to: 'gallery#create'
    post 'gallery/posts/update', to: 'gallery#update'
    post 'gallery/posts/like', to: 'gallery#like'
    post 'gallery/posts/unlike', to: 'gallery#unlike'
    post 'gallery/posts/delete', to: 'gallery#destroy'

    post 'channels/followed', to: 'channels#followed'
    post 'channels/my-favorites', to: 'channels#my_favorites'
    post 'channels/owned', to: 'channels#owned'
    post 'channels/featured', to: 'channels#featured'
    post 'channels/timeline', to: 'channels#timeline'
    post 'channels/search', to: 'channels#search'
    post 'channels/show', to: 'channels#show'
    post 'channels/create', to: 'channels#create'
    post 'channels/update', to: 'channels#update'
    post 'channels/follow', to: 'channels#follow'
    post 'channels/unfollow', to: 'channels#unfollow'
    post 'channels/favorite', to: 'channels#favorite'
    post 'channels/unfavorite', to: 'channels#unfavorite'
    post 'channels/mute/create', to: 'channels#mute_create'
    post 'channels/mute/delete', to: 'channels#mute_delete'
    post 'channels/mute/list', to: 'channels#mute_list'

    post 'admin/abuse-report/notification-recipient/list', to: 'admin_abuse_report_recipients#index'
    post 'admin/abuse-report/notification-recipient/show', to: 'admin_abuse_report_recipients#show'
    post 'admin/abuse-report/notification-recipient/create', to: 'admin_abuse_report_recipients#create'
    post 'admin/abuse-report/notification-recipient/update', to: 'admin_abuse_report_recipients#update'
    post 'admin/abuse-report/notification-recipient/delete', to: 'admin_abuse_report_recipients#destroy'
    post 'admin/abuse-user-reports', to: 'admin_reports#index'
    post 'admin/resolve-abuse-user-report', to: 'admin_reports#resolve'
    post 'admin/update-abuse-user-report', to: 'admin_reports#update'
    post 'admin/forward-abuse-user-report', to: 'admin_reports#forward'
    post 'admin/show-user', to: 'admin_users#show'
    post 'admin/show-users', to: 'admin_users#index'
    post 'admin/suspend-user', to: 'admin_users#suspend'
    post 'admin/unsuspend-user', to: 'admin_users#unsuspend'
    post 'admin/unset-mfa', to: 'admin_users#unset_mfa'
    post 'admin/unset-user-avatar', to: 'admin_users#unset_avatar'
    post 'admin/unset-user-banner', to: 'admin_users#unset_banner'
    post 'admin/update-user-note', to: 'admin_users#update_note'
    post 'admin/reset-password', to: 'admin_users#reset_password'
    post 'admin/get-user-ips', to: 'admin_users#ips'
    post 'admin/delete-all-files-of-a-user', to: 'admin_users#delete_all_files'
    post 'admin/accounts/find-by-email', to: 'admin_users#find_by_email'
    post 'admin/accounts/create', to: 'stub#unsupported'
    post 'admin/accounts/delete', to: 'stub#unsupported'
    post 'admin/delete-account', to: 'stub#unsupported'
    post 'admin/send-email', to: 'stub#unsupported'
    post 'admin/invite/create', to: 'admin_invites#create'
    post 'admin/invite/list', to: 'admin_invites#index'
    post 'admin/show-moderation-logs', to: 'admin_moderation_logs#index'
    post 'admin/roles/list', to: 'admin_roles#index'
    post 'admin/roles/show', to: 'admin_roles#show'
    post 'admin/roles/users', to: 'admin_roles#users'
    post 'admin/roles/create', to: 'admin_roles#create'
    post 'admin/roles/update', to: 'admin_roles#update'
    post 'admin/roles/delete', to: 'admin_roles#destroy'
    post 'admin/roles/assign', to: 'admin_roles#assign'
    post 'admin/roles/unassign', to: 'admin_roles#unassign'
    post 'admin/roles/update-default-policies', to: 'admin_roles#update_default_policies'

    match 'admin/*any', to: 'stub#noop', via: [:get, :post], format: false
    post 'v2/admin/emoji/list', to: 'stub#noop'
    post 'app/create', to: 'apps#create'
    post 'app/show', to: 'apps#show'
    match 'bubble-game/ranking', to: 'bubble_game#ranking', via: [:get, :post]
    post 'bubble-game/register', to: 'bubble_game#register'
    post 'ping', to: 'meta#ping'
    post 'promo/read', to: 'stub#no_content'
    post 'request-reset-password', to: 'credentials#request_reset_password'
    post 'reset-db', to: 'stub#unsupported'
    post 'reset-password', to: 'credentials#reset_password'
    match 'retention', to: 'retention#index', via: [:get, :post]
    post 'reversi/cancel-match', to: 'reversi#cancel_match'
    post 'reversi/games', to: 'reversi#games'
    post 'reversi/invitations', to: 'reversi#invitations'
    post 'reversi/match', to: 'reversi#match'
    post 'reversi/show-game', to: 'reversi#show_game'
    post 'reversi/surrender', to: 'reversi#surrender'
    post 'reversi/verify', to: 'reversi#verify'
    post 'i/change-password', to: 'i#change_password'
    post 'i/delete-account', to: 'stub#unsupported'
    post 'i/move', to: 'stub#unsupported'
    post 'i/update-email', to: 'i#update_email'
    post 'i/export-antennas', to: 'account_data#export_antennas'
    post 'i/export-blocking', to: 'account_data#export_blocking'
    post 'i/export-clips', to: 'account_data#export_clips'
    post 'i/export-favorites', to: 'account_data#export_favorites'
    post 'i/export-following', to: 'account_data#export_following'
    post 'i/export-mute', to: 'account_data#export_mute'
    post 'i/export-notes', to: 'account_data#export_notes'
    post 'i/export-user-lists', to: 'account_data#export_user_lists'
    post 'i/import-antennas', to: 'account_data#import_antennas'
    post 'i/import-blocking', to: 'account_data#import_blocking'
    post 'i/import-following', to: 'account_data#import_following'
    post 'i/import-muting', to: 'account_data#import_muting'
    post 'i/import-user-lists', to: 'account_data#import_user_lists'
    post 'export-custom-emojis', to: 'account_data#export_custom_emojis'
    post 'i/claim-achievement', to: 'achievements#claim'
    match 'users/achievements', to: 'achievements#index', via: [:get, :post]
    post 'invite/create', to: 'invites#create'
    post 'invite/delete', to: 'invites#destroy'
    post 'invite/list', to: 'invites#index'
    post 'invite/limit', to: 'invites#limit'
    match 'fetch-rss', to: 'fetch#rss', via: [:get, :post]
    post 'fetch-external-resources', to: 'fetch#external_resources'
    post 'test', to: 'stub#noop'
    post 'username/available', to: 'availability#username'
    post 'email-address/available', to: 'availability#email_address'
    post 'verify-email', to: 'credentials#verify_email'
  end
end
