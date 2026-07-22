# frozen_string_literal: true

resources :board_announcements, except: [:show] do
  member do
    post :publish
    post :unpublish
  end

  collection do
    post 'attachments', to: 'board_announcements#upload_attachment'
    delete 'attachments/:attachment_id', to: 'board_announcements#destroy_attachment', as: :attachment
  end
end

resources :drive_files, only: [:index, :destroy], path: 'drive/files' do
  collection do
    delete :destroy_orphaned
  end
end

resources :avatar_decorations, only: [:index, :new, :create, :edit, :update, :destroy] do
  member do
    post :approve
    post :redownload
  end

  collection do
    post :batch
    post :check_images
  end
end

resources :avatar_decoration_domain_blocks, only: [:index, :create, :destroy]
