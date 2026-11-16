# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Gallery endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:other_user) { Fabricate(:user) }
  let(:other_write_token) { Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: 'write').token }

  def encode(id)
    MisskeyCompat::MiId.encode(id)
  end

  def gallery_post(owner: account, **attributes)
    media = Fabricate(:media_attachment, account: owner)
    MisskeyGalleryPost.create!({ account: owner, title: 'Post', media_attachment_ids: [media.id] }.merge(attributes))
  end

  before do
    Setting.misskey_compat_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  describe 'creating, updating and deleting posts' do
    def call(path, **params)
      post "/api/gallery/#{path}", params: params, as: :json
      response.parsed_body
    end

    it 'creates a post from Drive files and blocks Drive deletion while it is in use', :attachment_processing do
      Setting.drive_enabled = true
      first = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'), sensitive: true)
      second = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

      body = call('posts/create', i: write_token, title: 'Trip', description: 'Photos', fileIds: [encode(first.id), encode(second.id)], isSensitive: true)

      expect(response).to have_http_status(200)
      expect(body).to include(title: 'Trip', description: 'Photos', isSensitive: true, likedCount: 0, isLiked: false, userId: encode(account.id), fileIds: [encode(first.id), encode(second.id)])
      expect(body[:files]).to match([include(id: encode(first.id), isSensitive: true), include(id: encode(second.id), isSensitive: false)])
      expect(body[:user]).to include(id: encode(account.id), username: account.username)
      expect(first.reload).to be_attached
      expect(DriveFile.orphaned).to_not include(first)
      expect(first.destroy).to be false
    end

    it 'reuses pointers on update and releases Drive files on update and delete', :attachment_processing do
      Setting.drive_enabled = true
      first, second = Array.new(2) { DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg')) }
      id = call('posts/create', i: write_token, title: 'Trip', fileIds: [encode(first.id), encode(second.id)], isSensitive: true)[:id]
      record = MisskeyGalleryPost.find(MisskeyCompat::MiId.decode(id))
      pointer_ids = record.media_attachment_ids

      expect { call('posts/update', i: write_token, postId: id, title: 'Trip 2', description: nil, fileIds: [encode(second.id)]) }
        .to_not(change { second.media_attachments.count })
      expect(response.parsed_body).to include(title: 'Trip 2', description: nil, isSensitive: true, fileIds: [encode(second.id)])
      expect(record.reload.media_attachment_ids).to eq([pointer_ids.last])
      expect(first.reload).to_not be_attached
      expect(MediaAttachment.unattached.where(id: pointer_ids).ids).to eq([pointer_ids.first])

      call('posts/delete', i: write_token, postId: id)

      expect(response).to have_http_status(204)
      expect(MisskeyGalleryPost).to_not exist(record.id)
      expect(second.reload).to_not be_attached
    end

    it 'accepts unattached media while Drive is disabled and protects it from the orphan vacuum' do
      media = Fabricate(:media_attachment, account: account)

      post '/api/gallery/posts/create', params: { i: write_token, title: 'Media', fileIds: [encode(media.id)] }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:fileIds]).to eq([encode(media.id)])
      expect(response.parsed_body[:isSensitive]).to be false
      expect(MediaAttachment.unattached).to_not include(media)
      expect(MediaAttachment.in_use).to include(media)
      expect(media.removable_with_chat_message?).to be false

      drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))
      post '/api/gallery/posts/create', params: { i: write_token, title: 'Drive off', fileIds: [encode(drive_file.id)] }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')
    end

    it 'validates parameters and rejects files of other accounts' do
      foreign = Fabricate(:media_attachment, account: other_user.account)
      media = Fabricate(:media_attachment, account: account)

      [
        [{ title: '', fileIds: [encode(media.id)] }, 'title'],
        [{ title: 'a' * 257, fileIds: [encode(media.id)] }, 'title'],
        [{ title: 'Post', fileIds: [] }, 'fileIds'],
        [{ title: 'Post', fileIds: [encode(media.id), encode(media.id)] }, 'fileIds'],
        [{ title: 'Post', description: 1, fileIds: [encode(media.id)] }, 'description'],
        [{ title: 'Post', fileIds: [encode(media.id)], isSensitive: 'yes' }, 'isSensitive'],
      ].each do |params, field|
        post '/api/gallery/posts/create', params: params.merge(i: write_token), as: :json

        expect(response).to have_http_status(400)
        expect(response.parsed_body.dig(:error, :info, :param)).to eq("#/properties/#{field}")
      end

      post '/api/gallery/posts/create', params: { i: write_token, title: 'Post', fileIds: [encode(foreign.id)] }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')

      post '/api/gallery/posts/create', params: { i: read_token, title: 'Post', fileIds: [encode(media.id)] }, as: :json

      expect(response).to have_http_status(403)
      expect(MisskeyGalleryPost.count).to eq(0)
    end

    it 'lets only the owner update and the owner or a moderator delete' do
      record = gallery_post(owner: other_user.account)
      moderator = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports]))
      moderator_token = Fabricate(:accessible_access_token, resource_owner_id: moderator.id, scopes: 'write').token

      post '/api/gallery/posts/update', params: { i: write_token, postId: encode(record.id), title: 'Hijack' }, as: :json

      expect(response).to have_http_status(404)
      expect(record.reload.title).to eq('Post')

      post '/api/gallery/posts/delete', params: { i: write_token, postId: encode(record.id) }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body[:error]).to include(code: 'ACCESS_DENIED', id: 'c86e09de-1c48-43ac-a435-1c7e42ed4496')

      post '/api/gallery/posts/delete', params: { i: moderator_token, postId: encode(record.id) }, as: :json

      expect(response).to have_http_status(204)
      expect(MisskeyGalleryPost).to_not exist(record.id)

      post '/api/gallery/posts/delete', params: { i: write_token, postId: encode(record.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_POST', id: 'ae52f367-4bd7-4ecd-afc6-5672fff427f5')
    end
  end

  describe 'likes' do
    let(:record) { gallery_post(owner: other_user.account) }

    def like(path, token = write_token, post_id: encode(record.id))
      post "/api/gallery/posts/#{path}", params: { i: token, postId: post_id }, as: :json
      response.body.empty? ? nil : response.parsed_body[:error]
    end

    it 'likes and unlikes a post with Misskey errors' do
      expect(like('like')).to be_nil
      expect(record.reload.likes_count).to eq(1)
      expect(like('like')).to include(code: 'ALREADY_LIKED', id: '40e9ed56-a59c-473a-bf3f-f289c54fb5a7')
      expect(like('like', other_write_token)).to include(code: 'YOUR_POST', id: 'f78f1511-5ebc-4478-a888-1198d752da68')
      expect(like('like', post_id: encode(record.id + 1))).to include(code: 'NO_SUCH_POST', id: '56c06af3-1287-442f-9701-c93f7c4a62ff')
      expect(like('unlike')).to be_nil
      expect(record.reload.likes_count).to eq(0)
      expect(like('unlike')).to include(code: 'NOT_LIKED', id: 'e3e8e06e-be37-41f7-a5b4-87a8250288f0')
    end

    it 'lists liked posts and marks them as liked' do
      like('like')

      post '/api/i/gallery/likes', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(include(id: encode(record.likes.first.id), post: include(id: encode(record.id), likedCount: 1, isLiked: true)))

      post '/api/gallery/posts/show', params: { i: read_token, postId: encode(record.id) }, as: :json

      expect(response.parsed_body).to include(isLiked: true, likedCount: 1)
    end
  end

  describe 'listing posts' do
    def listed_ids(path, **params)
      post "/api/#{path}", params: params, as: :json
      response.parsed_body.pluck(:id)
    end

    it 'lists posts globally, per user, for the owner, and by popularity while hiding suspended accounts' do
      older = gallery_post(likes_count: 1)
      newer = gallery_post(owner: other_user.account, likes_count: 3)
      unliked = gallery_post
      suspended = gallery_post(owner: Fabricate(:account, suspended_at: Time.current), likes_count: 9)

      expect(listed_ids('gallery/posts')).to eq([unliked, newer, older].map { |item| encode(item.id) })
      expect(response.parsed_body.first).to_not have_key(:isLiked)
      expect(listed_ids('gallery/posts', untilId: encode(newer.id), limit: 1)).to eq([encode(older.id)])
      expect(listed_ids('gallery/posts', sinceId: encode(older.id), limit: 1)).to eq([encode(newer.id)])
      expect(listed_ids('users/gallery/posts', userId: encode(account.id))).to eq([unliked, older].map { |item| encode(item.id) })
      expect(listed_ids('users/gallery/posts', userId: encode(suspended.account_id))).to eq([])
      expect(listed_ids('i/gallery/posts', i: read_token)).to eq([unliked, older].map { |item| encode(item.id) })
      expect(response.parsed_body.first).to include(isLiked: false)
      expect(listed_ids('gallery/popular')).to eq([newer, older].map { |item| encode(item.id) })

      post '/api/gallery/posts/show', params: { postId: encode(suspended.id) }, as: :json

      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_POST', id: '1137bf14-c5b0-4604-85bb-5b5371b1cd45')
    end

    it 'ranks recently liked new posts for featured and orders them by id' do
      liked_old_post = travel_to(10.days.ago) { gallery_post(owner: other_user.account) }
      first = gallery_post(owner: other_user.account)
      second = gallery_post(owner: other_user.account)
      gallery_post(owner: other_user.account)
      [liked_old_post, first, second].each { |item| MisskeyGalleryLike.create!(account: account, misskey_gallery_post: item) }

      expect(listed_ids('gallery/featured')).to eq([second, first].map { |item| encode(item.id) })
      expect(listed_ids('gallery/featured', untilId: encode(second.id))).to eq([encode(first.id)])

      post '/api/i/gallery/posts', params: {}, as: :json

      expect(response).to have_http_status(401)
    end
  end
end
