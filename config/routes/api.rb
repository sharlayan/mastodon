# frozen_string_literal: true

namespace :api, format: false do
  # OEmbed
  get '/oembed', to: 'oembed#show', as: :oembed

  # Experimental JSON / REST API
  namespace :v1_alpha do
    resources :async_refreshes, only: :show
  end

  # TODO: Remove once apps switch over to v1
  scope :v1_alpha, as: :v1_alpha, module: :v1 do
    resources :accounts, only: [] do
      resources :collections, only: [:index]
      resources :in_collections, only: [:index]
    end

    resources :collections, only: [:show, :create, :update, :destroy] do
      resources :items, only: [:create, :destroy], controller: 'collection_items' do
        member do
          post :revoke
        end
      end
    end
  end

  # JSON / REST API
  namespace :v1 do
    resources :statuses, only: [:index, :create, :show, :update, :destroy] do
      scope module: :statuses do
        resources :reblogged_by, controller: :reblogged_by_accounts, only: :index
        resources :favourited_by, controller: :favourited_by_accounts, only: :index
        resources :reacted_by, controller: :reacted_by_accounts, only: :index
        resource :reblog, only: :create
        resource :context, only: :show
        post :unreblog, to: 'reblogs#destroy'

        resources :quotes, only: :index do
          member do
            post :revoke
          end
        end

        resource :favourite, only: :create
        post :unfavourite, to: 'favourites#destroy'

        # foreign custom emojis are encoded as shortcode@domain.tld
        # the constraint prevents rails from interpreting the ".tld" as a filename extension
        post '/react/:id', to: 'reactions#create', constraints: { id: %r{[^/]+} }
        post '/unreact/:id', to: 'reactions#destroy', constraints: { id: %r{[^/]+} }

        resource :bookmark, only: :create
        post :unbookmark, to: 'bookmarks#destroy'

        resources :clips, only: :index

        resource :mute, only: :create
        post :unmute, to: 'mutes#destroy'

        resource :pin, only: :create
        post :unpin, to: 'pins#destroy'

        resource :history, only: :show
        resource :source, only: :show

        resource :interaction_policy, only: :update

        post :translate, to: 'translations#create'
      end
    end

    namespace :timelines do
      resource :direct, only: :show, controller: :direct
      resource :home, only: :show, controller: :home
      resource :public, only: :show, controller: :public
      resource :link, only: :show, controller: :link
      resources :tag, only: :show
      resources :list, only: :show
      resources :antenna, only: :show
    end

    with_options to: 'streaming#index' do
      get '/streaming'
      get '/streaming/(*any)'
    end

    resources :custom_emojis, only: [:index]
    resources :favorite_emojis, only: [:index, :create, :destroy], param: :name
    resources :avatar_decorations, only: [:index]
    post   '/avatar_decoration_mutes',     to: 'avatar_decorations#create_mute',  as: :avatar_decoration_mutes
    delete '/avatar_decoration_mutes/:id', to: 'avatar_decorations#destroy_mute', as: :avatar_decoration_mute
    resources :reaction_mutes, only: [:index, :create, :destroy]
    resources :custom_emoji_mutes, only: [:index, :create, :destroy] do
      collection do
        put :preferences
      end
    end
    resources :suggestions, only: [:index, :destroy]
    resources :scheduled_statuses, only: [:index, :show, :update, :destroy]
    resources :preferences, only: [:index]
    resource :appearance, only: [:update], controller: :appearance
    resources :donation_campaigns, only: [:index]

    resources :annual_reports, only: [:index, :show] do
      member do
        post :read
        post :generate
        get :state
      end
    end

    resources :announcements, only: [:index] do
      scope module: :announcements do
        resources :reactions, only: [:update, :destroy]
      end

      member do
        post :dismiss
      end
    end

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

    resources :conversations, only: [:index, :destroy] do
      collection do
        get 'with_account/:account_id', action: :with_account
      end

      member do
        post :read
        post :unread
        get  :statuses
      end
    end

    resources :media, only: [:create, :update, :show, :destroy]

    namespace :drive do
      resources :files, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :attach
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
    end

    resources :blocks, only: [:index]
    resources :mutes, only: [:index]
    resources :favourites, only: [:index]
    resources :reactions, only: [:index] do
      collection do
        get :summary
      end
    end
    resources :bookmarks, only: [:index]
    resources :reports, only: [:create]
    resources :trends, only: [:index], controller: 'trends/tags'
    resources :filters, only: [:index, :create, :show, :update, :destroy]
    resources :endorsements, only: [:index]
    resources :markers, only: [:index, :create]

    resource :profile, only: [:show, :update] do
      scope module: :profile do
        resource :avatar, only: :destroy
        resource :header, only: :destroy
      end
    end

    namespace :apps do
      get :verify_credentials, to: 'credentials#show'
    end

    resources :apps, only: [:create]

    namespace :trends do
      resources :tags, only: [:index]
      resources :links, only: [:index]
      resources :statuses, only: [:index]
    end

    namespace :emails do
      resources :confirmations, only: [:create]
      get :check_confirmation, to: 'confirmations#check'
    end

    resource :instance, only: [:show] do
      scope module: :instances do
        resources :peers, only: [:index]
        resources :rules, only: [:index]
        resources :domain_blocks, only: [:index]
        resources :terms_of_service, only: [:index, :show], param: :date

        resource :privacy_policy, only: [:show]
        resource :extended_description, only: [:show]
        resource :translation_languages, only: [:show]
        resource :languages, only: [:show]
        resource :activity, only: [:show], controller: :activity
      end
    end

    namespace :peers do
      get :search, to: 'search#index'
    end

    namespace :domain_blocks do
      resource :preview, only: [:show]
    end

    resource :domain_blocks, only: [:show, :create, :destroy]
    resource :domain_mutes, only: [:show, :create, :destroy]

    resource :directory, only: [:show]

    resources :follow_requests, only: [:index] do
      member do
        post :authorize
        post :reject
      end
    end

    namespace :notifications do
      resources :requests, only: [:index, :show] do
        collection do
          post :accept, to: 'requests#accept_bulk'
          post :dismiss, to: 'requests#dismiss_bulk'
          get :merged, to: 'requests#merged?'
        end

        member do
          post :accept
          post :dismiss
        end
      end

      resource :policy, only: [:show, :update]
    end

    resources :notifications, only: [:index, :show, :destroy] do
      collection do
        post :clear
        delete :destroy_multiple
        get :unread_count
      end

      member do
        post :dismiss
      end
    end

    namespace :accounts do
      get :verify_credentials, to: 'credentials#show'
      patch :update_credentials, to: 'credentials#update'
      resource :search, only: :show, controller: :search
      resource :lookup, only: :show, controller: :lookup
      resources :relationships, only: :index
      resources :familiar_followers, only: :index
    end

    resources :account_switches, only: [:index, :destroy] do
      collection do
        get    :linked_unread_counts
        post   :push_forward, action: :create_push_forward
        delete :push_forward, action: :destroy_push_forward
      end
    end

    resources :accounts, only: [:index, :create, :show] do
      scope module: :accounts do
        resources :statuses, only: :index
        resources :followers, only: :index, controller: :follower_accounts
        resources :following, only: :index, controller: :following_accounts
        resources :lists, only: :index
        resources :circles, only: :index
        resources :clips, only: :index
        resources :antennas, only: :index
        resources :exclude_antennas, only: :index
        resources :identity_proofs, only: :index
        resources :featured_tags, only: :index
        resources :endorsements, only: :index
        resources :email_subscriptions, only: :create
      end

      resources :collections, only: [:index]
      resources :in_collections, only: [:index]

      member do
        post :follow
        post :unfollow
        post :remove_from_followers
        post :block
        post :unblock
        post :mute
        post :unmute
        post :refetch
      end

      scope module: :accounts do
        post :pin, to: 'endorsements#create'
        post :endorse, to: 'endorsements#create'
        post :unpin, to: 'endorsements#destroy'
        post :unendorse, to: 'endorsements#destroy'
        resource :note, only: :create
      end
    end

    resources :tags, only: [:show] do
      member do
        post :follow
        post :unfollow
        post :feature
        post :unfeature
      end
    end

    resources :followed_tags, only: [:index]

    resources :lists, only: [:index, :create, :show, :update, :destroy] do
      resource :accounts, only: [:show, :create, :destroy], module: :lists
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

    resources :antennas, only: [:index, :create, :show, :update, :destroy] do
      scope module: :antennas do
        resource :accounts, only: [:show, :create, :destroy]
        resource :exclude_accounts, only: [:show, :create, :destroy]
        resource :domains, only: [:show, :create, :destroy]
        resource :exclude_domains, only: [:show, :create, :destroy]
        resource :tags, only: [:show, :create, :destroy]
        resource :exclude_tags, only: [:show, :create, :destroy]
      end
    end

    namespace :featured_tags do
      resources :suggestions, only: :index
    end

    resources :featured_tags, only: [:index, :create, :destroy]

    resources :polls, only: [:show] do
      resources :votes, only: :create, module: :polls
    end

    namespace :push do
      resource :subscription, only: [:create, :show, :update, :destroy]
    end

    namespace :admin do
      resources :accounts, only: [:index, :show, :destroy] do
        member do
          post :enable
          post :unsensitive
          post :unsilence
          post :unsuspend
          post :approve
          post :reject
        end

        resource :action, only: [:create], controller: 'account_actions'
      end

      resources :reports, only: [:index, :update, :show] do
        member do
          post :assign_to_self
          post :unassign
          post :reopen
          post :resolve
        end
      end

      resources :domain_allows, only: [:index, :show, :create, :destroy]
      resources :domain_blocks, only: [:index, :show, :update, :create, :destroy]
      resources :email_domain_blocks, only: [:index, :show, :create, :destroy]
      resources :ip_blocks, only: [:index, :show, :update, :create, :destroy]

      namespace :trends do
        concern :approvable do
          member do
            post :approve
            post :reject
          end
        end
        with_options only: [:index], concerns: :approvable do
          resources :tags
          resources :links
          resources :statuses
        end

        namespace :links do
          resources :preview_card_providers, only: [:index], path: :publishers, concerns: :approvable
        end
      end

      post :measures, to: 'measures#create'
      post :dimensions, to: 'dimensions#create'
      post :retention, to: 'retention#create'

      resources :canonical_email_blocks, only: [:index, :create, :show, :destroy] do
        collection do
          post :test
        end
      end

      resources :tags, only: [:index, :show, :update]
    end

    resources :collections, only: [:show, :create, :update, :destroy] do
      resources :items, only: [:create, :destroy], controller: 'collection_items' do
        member do
          post :revoke
        end
      end
    end
  end

  namespace :v2 do
    get '/search', to: 'search#index', as: :search

    resources :media, only: [:create]
    resources :suggestions, only: [:index]
    resource :instance, only: [:show]
    resources :filters, only: [:index, :create, :show, :update, :destroy] do
      scope module: :filters do
        resources :keywords, only: [:index, :create]
        resources :statuses, only: [:index, :create]
      end
    end

    namespace :filters do
      resources :keywords, only: [:show, :update, :destroy]
      resources :statuses, only: [:show, :destroy]
    end

    namespace :admin do
      resources :accounts, only: [:index]
    end

    namespace :notifications do
      resource :policy, only: [:show, :update]
    end

    resources :notifications, param: :group_key, only: [:index, :show] do
      collection do
        post :clear
        get :unread_count
      end

      member do
        post :dismiss
      end

      resources :accounts, only: [:index], module: :notifications
    end
  end

  namespace :web do
    resource :settings, only: [:update]
    resource :local_settings, only: [:show, :update]
    resources :embeds, only: [:show]
    resources :push_subscriptions, only: [:create, :destroy, :update]
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
    post 'stats', to: 'meta#stats'
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

    post 'sw/register', to: 'sw#register'
    post 'sw/unregister', to: 'sw#unregister'
    post 'sw/show-registration', to: 'sw#show_registration'

    post 'notes/timeline', to: 'notes#timeline'
    post 'notes/local-timeline', to: 'notes#local_timeline'
    post 'notes/hybrid-timeline', to: 'notes#hybrid_timeline'
    post 'notes/global-timeline', to: 'notes#global_timeline'
    post 'notes/show', to: 'notes#show'
    post 'notes/update', to: 'notes#update'
    post 'notes/scheduled/list', to: 'notes#scheduled_list'
    post 'notes/scheduled/cancel', to: 'notes#scheduled_cancel'
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
    post 'drive/files', to: 'drive#unavailable'
    post 'drive/files/show', to: 'drive#unavailable'
    post 'drive/files/update', to: 'drive#unavailable'
    post 'drive/files/delete', to: 'drive#unavailable'
    post 'drive/files/find', to: 'drive#unavailable'
    post 'drive/files/upload-from-url', to: 'drive#unavailable'
    post 'drive/files/move-bulk', to: 'drive#unavailable'
    post 'drive/folders', to: 'drive#unavailable'
    post 'drive/folders/show', to: 'drive#unavailable'
    post 'drive/folders/create', to: 'drive#unavailable'
    post 'drive/folders/update', to: 'drive#unavailable'
    post 'drive/folders/delete', to: 'drive#unavailable'

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
    post 'users/lists/create-from-public', to: 'lists#create_from_public'
    post 'notes/user-list-timeline', to: 'lists#timeline'

    post 'antennas/list', to: 'antennas#index'
    post 'antennas/show', to: 'antennas#show'
    post 'antennas/create', to: 'antennas#create'
    post 'antennas/update', to: 'antennas#update'
    post 'antennas/delete', to: 'antennas#destroy'
    post 'antennas/notes', to: 'antennas#notes'

    post 'announcements', to: 'announcements#index'
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

    post 'pages/featured', to: 'pages#empty'
    post 'i/pages', to: 'pages#empty'
    post 'i/page-likes', to: 'pages#empty'
    post 'users/pages', to: 'pages#empty'
    post 'pages/show', to: 'pages#unsupported'
    post 'pages/like', to: 'pages#unsupported'
    post 'pages/unlike', to: 'pages#unsupported'
    post 'pages/create', to: 'pages#unsupported'
    post 'pages/update', to: 'pages#unsupported'
    post 'pages/delete', to: 'pages#unsupported'

    post 'chat/history', to: 'chat#empty'
    post 'chat/read-all', to: 'chat#noop'
    post 'chat/messages/user-timeline', to: 'chat#empty'
    post 'chat/messages/room-timeline', to: 'chat#empty'
    post 'chat/messages/show', to: 'chat#noop'
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

    post 'flash/my', to: 'flash#empty'
    post 'flash/featured', to: 'flash#empty'
    post 'flash/search', to: 'flash#empty'
    post 'flash/my-likes', to: 'flash#empty'
    post 'flash/show', to: 'flash#noop'
    post 'flash/update', to: 'flash#noop'
    post 'flash/like', to: 'flash#noop'
    post 'flash/unlike', to: 'flash#noop'
    post 'users/flashs', to: 'flash#empty'

    post 'gallery/posts', to: 'gallery#empty'
    post 'gallery/featured', to: 'gallery#empty'
    post 'gallery/popular', to: 'gallery#empty'
    post 'i/gallery/posts', to: 'gallery#empty'
    post 'i/gallery/likes', to: 'gallery#empty'
    post 'users/gallery/posts', to: 'gallery#empty'
    post 'gallery/posts/show', to: 'gallery#noop'
    post 'gallery/posts/create', to: 'gallery#noop'
    post 'gallery/posts/update', to: 'gallery#noop'
    post 'gallery/posts/like', to: 'gallery#noop'
    post 'gallery/posts/unlike', to: 'gallery#noop'

    post 'channels/followed', to: 'channels#empty'
    post 'channels/my-favorites', to: 'channels#empty'
    post 'channels/owned', to: 'channels#empty'
    post 'channels/featured', to: 'channels#empty'
    post 'channels/timeline', to: 'channels#empty'
    post 'channels/search', to: 'channels#empty'
    post 'channels/show', to: 'channels#noop'
    post 'channels/create', to: 'channels#noop'
    post 'channels/update', to: 'channels#noop'
    match 'channels/follow', to: 'channels#noop', via: [:post]
    match 'channels/unfollow', to: 'channels#noop', via: [:post]
    match 'channels/favorite', to: 'channels#noop', via: [:post]
    match 'channels/unfavorite', to: 'channels#noop', via: [:post]
    post 'channels/mute/create', to: 'channels#noop'
    post 'channels/mute/delete', to: 'channels#noop'

    match 'admin/*any', to: 'stub#noop', via: [:get, :post], format: false
    post 'i/claim-achievement', to: 'stub#no_content'
    match 'users/achievements', to: 'stub#empty', via: [:get, :post]
    post 'invite/create', to: 'stub#noop'
    post 'invite/delete', to: 'stub#no_content'
    match 'invite/list', to: 'stub#empty', via: [:get, :post]
    match 'invite/limit', to: 'stub#invite_limit', via: [:get, :post]
    match 'fetch-rss', to: 'stub#noop', via: [:get, :post]
    post 'fetch-external-resources', to: 'stub#noop'
  end
end
