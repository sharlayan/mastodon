# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Play endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:other_user) { Fabricate(:user) }
  let(:other_write_token) { Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: 'write').token }

  def encode(id)
    MisskeyCompat::MiId.encode(id)
  end

  def play(owner: account, **attributes)
    MisskeyFlash.create!({ account: owner, title: 'Play', summary: 'Summary', script: '/// @ 0.16.0', permissions: [] }.merge(attributes))
  end

  def call(path, **params)
    post "/api/#{path}", params: params, as: :json
    response.body.empty? ? nil : response.parsed_body
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'writing plays' do
    it 'creates, shows, updates and deletes a play without running its script' do
      script = "/// @ 0.16.0\nMk:dialog('hi' 'there')"

      body = call('flash/create', i: write_token, title: 'Hello', summary: 'Greets', script: script, permissions: ['write:notes'], visibility: 'private')

      expect(response).to have_http_status(200)
      expect(body).to include(title: 'Hello', summary: 'Greets', script: script, visibility: 'private', likedCount: 0, userId: encode(account.id))
      expect(body.keys).to_not include('isLiked', 'permissions')
      record = MisskeyFlash.find(MisskeyCompat::MiId.decode(body[:id]))
      expect(record.permissions).to eq(['write:notes'])

      expect(call('flash/update', i: write_token, flashId: body[:id], title: 'Renamed', visibility: 'public', permissions: [])).to be_nil
      expect(response).to have_http_status(204)
      expect(record.reload).to have_attributes(title: 'Renamed', summary: 'Greets', visibility: 'public', permissions: [])

      expect(call('flash/show', flashId: body[:id])).to include(title: 'Renamed', user: include(id: encode(account.id)))
      expect(call('flash/delete', i: write_token, flashId: body[:id])).to be_nil
      expect(MisskeyFlash).to_not exist(record.id)
    end

    it 'validates parameters and requires the write scope' do
      base = { title: 'T', summary: 'S', script: '', permissions: [] }

      [
        [base.except(:script), 'script'],
        [base.merge(title: 'a' * 257), 'title'],
        [base.merge(permissions: 'read:account'), 'permissions'],
        [base.merge(visibility: 'followers'), 'visibility'],
      ].each do |params, field|
        expect(call('flash/create', i: write_token, **params).dig(:error, :info, :param)).to eq("#/properties/#{field}")
      end

      expect(call('flash/create', i: read_token, **base).dig(:error, :code)).to eq('PERMISSION_DENIED')
      expect(MisskeyFlash.count).to eq(0)
    end

    it 'lets only the owner update and the owner or a moderator delete' do
      record = play(owner: other_user.account)
      moderator = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports]))
      moderator_token = Fabricate(:accessible_access_token, resource_owner_id: moderator.id, scopes: 'write').token

      expect(call('flash/update', i: write_token, flashId: encode(record.id), title: 'Hijack')[:error]).to include(code: 'ACCESS_DENIED', id: '08e60c88-5948-478e-a132-02ec701d67b2')
      expect(call('flash/delete', i: write_token, flashId: encode(record.id))[:error]).to include(code: 'ACCESS_DENIED', id: '1036ad7b-9f92-4fff-89c3-0e50dc941704')
      expect(call('flash/delete', i: moderator_token, flashId: encode(record.id))).to be_nil
      expect(MisskeyFlash).to_not exist(record.id)
      expect(call('flash/show', flashId: encode(record.id))[:error]).to include(code: 'NO_SUCH_FLASH', id: 'f0d34a1a-d29a-401d-90ba-1982122b5630')
    end
  end

  describe 'likes' do
    let(:record) { play(owner: other_user.account, visibility: 'private') }

    def like(path, token = write_token, flash_id: encode(record.id))
      call("flash/#{path}", i: token, flashId: flash_id)&.dig(:error)
    end

    it 'likes and unlikes a play with Misskey errors' do
      expect(like('like')).to be_nil
      expect(record.reload.likes_count).to eq(1)
      expect(like('like')).to include(code: 'ALREADY_LIKED', id: '010065cf-ad43-40df-8067-abff9f4686e3')
      expect(like('like', other_write_token)).to include(code: 'YOUR_FLASH', id: '3fd8a0e7-5955-4ba9-85bb-bf3e0c30e13b')
      expect(like('like', flash_id: encode(record.id + 1))).to include(code: 'NO_SUCH_FLASH', id: 'c07c1491-9161-4c5c-9d75-01906f911f73')
      expect(like('unlike')).to be_nil
      expect(record.reload.likes_count).to eq(0)
      expect(like('unlike')).to include(code: 'NOT_LIKED', id: '755f25a7-9871-4f65-9f34-51eaad9ae0ac')
    end

    it 'lists liked plays with an optional search and marks them as liked' do
      like('like')
      other = play(owner: other_user.account, title: 'Other')
      MisskeyFlashLike.create!(account: account, misskey_flash: other)

      expect(call('flash/my-likes', i: read_token).pluck(:id)).to eq([other, record].map { |item| encode(item.likes.first.id) })
      expect(call('flash/my-likes', i: read_token, search: 'other')).to contain_exactly(include(flash: include(id: encode(other.id), isLiked: true, likedCount: 1)))
      expect(call('flash/show', i: read_token, flashId: encode(record.id))).to include(isLiked: true, visibility: 'private')
    end
  end

  describe 'listing plays' do
    it 'lists featured, searched, per-user and own plays with Misskey visibility rules' do
      popular = play(title: 'Popular game', likes_count: 5)
      liked = play(owner: other_user.account, title: 'Puzzle', summary: 'A popular puzzle', likes_count: 2)
      hidden = play(title: 'Secret popular', visibility: 'private', likes_count: 9)
      play(owner: Fabricate(:account, suspended_at: Time.current), title: 'Suspended popular', likes_count: 9)
      fresh = play(title: 'Fresh')

      expect(call('flash/featured').pluck(:id)).to eq([popular, liked].map { |item| encode(item.id) })
      expect(call('flash/featured', offset: 1, limit: 1).pluck(:id)).to eq([encode(liked.id)])
      expect(call('flash/search', query: 'popular').pluck(:id)).to eq([liked, popular].map { |item| encode(item.id) })
      expect(call('flash/search', query: 'popular game').pluck(:id)).to eq([encode(popular.id)])
      expect(call('flash/search', query: '').dig(:error, :info, :param)).to eq('#/properties/query')
      expect(call('users/flashs', userId: encode(account.id)).pluck(:id)).to eq([fresh, popular].map { |item| encode(item.id) })
      expect(call('flash/my', i: read_token).pluck(:id)).to eq([fresh, hidden, popular].map { |item| encode(item.id) })
      expect(response.parsed_body.first).to_not have_key(:isLiked)
      expect(call('flash/my', i: read_token, untilId: encode(hidden.id)).pluck(:id)).to eq([encode(popular.id)])
      expect(call('flash/my').dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')
    end
  end
end
