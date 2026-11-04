# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat conversation list' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses').token }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  before { Setting.chat_enabled = true }
  after { Setting.chat_enabled = false }

  def room_with_reactions
    members = Array.new(3) { Fabricate(:account) }
    ChatConversation.create!(conversation_type: :group, owner_account: user.account, title: 'Room').tap do |room|
      room.memberships.create!(account: user.account, role: :owner)
      members.each { |member| room.memberships.create!(account: member) }
      message = room.messages.create!(account: user.account, text: 'hello')
      members.each { |member| message.reactions.create!(account: member, reaction: '👍') }
      room.update!(last_message: message)
    end
  end

  def queries_during
    sql = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, payload| sql << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached] }
    yield
    sql
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'does not multiply members by reactions in one query' do
    room_with_reactions

    sql = queries_during { get '/api/v1/chat/conversations', headers: headers }

    expect(response).to have_http_status(200)
    expect(sql).to(be_none { |query| query.include?('LEFT OUTER JOIN "chat_message_reactions"') })
  end

  it 'lists every member, not only the viewer' do
    room = room_with_reactions

    get '/api/v1/chat/conversations', headers: headers

    expect(response.parsed_body.first[:accounts].size).to eq(room.accounts.size)
    expect(response.parsed_body.first[:last_message][:reactions].size).to eq(3)
    expect(response.parsed_body.first[:current_role]).to eq('owner')
  end

  it 'does not query more for each conversation' do
    room_with_reactions
    Fabricate(:user)
    get '/api/v1/chat/conversations', headers: headers
    one = queries_during { get '/api/v1/chat/conversations', headers: headers }.size

    Array.new(4) { room_with_reactions }
    many = queries_during { get '/api/v1/chat/conversations', headers: headers }.size

    expect(many).to be <= one + 2
  end

  it 'filters the admin list without a Cartesian product' do
    admin = Fabricate(:admin_user)
    room = room_with_reactions
    sign_in admin

    sql = queries_during { get admin_chat_conversations_path(account_id: user.account_id) }

    expect(response).to have_http_status(200)
    expect(response.body).to include(admin_chat_conversation_path(room))
    expect(sql).to(be_none { |query| query.include?('LEFT OUTER JOIN "accounts"') && query.include?('"chat_memberships"') })
  end

  describe 'sending the first direct message with the Misskey API' do
    let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone', last_webfingered_at: 1.year.ago) }
    let(:misskey_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

    before do
      Setting.misskey_compat_enabled = true
      Setting.chat_federation_enabled = true
    end

    after do
      Setting.misskey_compat_enabled = false
      Setting.chat_federation_enabled = false
    end

    it 'refreshes the remote account outside the database transaction' do
      remote
      baseline = ActiveRecord::Base.connection.open_transactions
      during_fetch = nil
      service = instance_double(ActivityPub::FetchRemoteAccountService)
      allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_return(service)
      allow(service).to receive(:call) do
        during_fetch = ActiveRecord::Base.connection.open_transactions
        remote
      end

      post '/api/chat/messages/create-to-user', params: { i: misskey_token, toUserId: MisskeyCompat::MiId.encode(remote.id), text: 'hello' }, as: :json

      expect(response).to have_http_status(200)
      expect(during_fetch).to eq(baseline)
    end

    it 'leaves no empty conversation when the message is refused' do
      remote

      expect do
        post '/api/chat/messages/create-to-user', params: { i: misskey_token, toUserId: MisskeyCompat::MiId.encode(remote.id), fileIds: [MisskeyCompat::MiId.encode(Fabricate(:media_attachment, account: Fabricate(:account), status: nil).id)] }, as: :json
      end.to_not change(ChatConversation, :count)
    end
  end
end
