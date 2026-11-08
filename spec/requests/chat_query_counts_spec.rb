# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat query counts' do
  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:room) { group_with_members(2) }

  before do
    Setting.chat_enabled = true
    Fabricate(:custom_emoji, shortcode: 'blobcat')
  end

  after { Setting.chat_enabled = false }

  def queries_during
    sql = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, payload| sql << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached] }
    yield
    sql
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def group_with_members(count, display_name: 'Member :blobcat:')
    members = Array.new(count) { Fabricate(:user, account: Fabricate(:account, display_name: display_name)).account }
    ChatConversation.create!(conversation_type: :group, owner_account: user.account, title: 'Room').tap do |record|
      record.memberships.create!(account: user.account, role: :owner)
      members.each { |member| record.memberships.create!(account: member) }
    end
  end

  def message_with_reactions(conversation)
    message = conversation.messages.create!(account: user.account, text: 'hello searchable')
    conversation.accounts.where.not(id: user.account_id).find_each do |member|
      emoji = Fabricate(:custom_emoji, shortcode: "emoji#{SecureRandom.hex(4)}")
      message.reactions.create!(account: member, reaction: ":#{emoji.shortcode}:")
    end
    conversation.update!(last_message: message)
    message
  end

  describe 'listing messages' do
    it 'looks custom emoji up once for every reaction' do
      message_with_reactions(room)
      get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers
      one = queries_during { get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers }

      4.times { message_with_reactions(room) }
      many = queries_during { get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers }

      expect(response.parsed_body.first[:reactions].pluck(:url)).to all(be_present)
      expect(many.count { |query| query.include?('"custom_emojis"') }).to eq(one.count { |query| query.include?('"custom_emojis"') })
    end
  end

  describe 'searching messages' do
    it 'looks custom emoji up once for every reaction' do
      message_with_reactions(room)
      get '/api/v1/chat/messages/search', headers: headers, params: { q: 'searchable' }
      one = queries_during { get '/api/v1/chat/messages/search', headers: headers, params: { q: 'searchable' } }

      4.times { message_with_reactions(room) }
      many = queries_during { get '/api/v1/chat/messages/search', headers: headers, params: { q: 'searchable' } }

      expect(response.parsed_body.size).to eq(5)
      expect(many.count { |query| query.include?('"custom_emojis"') }).to eq(one.count { |query| query.include?('"custom_emojis"') })
    end
  end

  describe 'broadcasting a message' do
    it 'looks custom emoji up once for every reaction' do
      message = message_with_reactions(group_with_members(1, display_name: 'Member'))
      one = queries_during { Sharlayan::ChatBroadcastPayload.new(ChatMessage.find(message.id), REST::ChatMessageSerializer).for(user.account) }

      message = message_with_reactions(group_with_members(4, display_name: 'Member'))
      many = queries_during { Sharlayan::ChatBroadcastPayload.new(ChatMessage.find(message.id), REST::ChatMessageSerializer).for(user.account) }

      expect(many.count { |query| query.include?('"custom_emojis"') }).to eq(one.count { |query| query.include?('"custom_emojis"') })
    end
  end
end
