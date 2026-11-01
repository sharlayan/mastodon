# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings / Exports / Chat' do
  let(:user) { Fabricate(:user) }
  let(:other_user) { Fabricate(:user) }

  before { sign_in user }

  describe 'GET /settings/exports/chat' do
    it 'returns not found while native chat is disabled' do
      Setting.chat_enabled = false

      get '/settings/exports/chat.json'

      expect(response).to have_http_status(404)
    end

    it 'downloads the signed-in account chat data as JSON' do
      Setting.chat_enabled = true
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [user.account_id, other_user.account_id].sort.join(':'))
      conversation.memberships.create!([{ account: user.account }, { account: other_user.account }])
      message = conversation.messages.create!(account: user.account, text: 'hello')

      get '/settings/exports/chat.json'

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Content-Disposition']).to include('chat.json')
      expect(response.parsed_body.dig('chat_conversations', 0, 'messages', 0)).to include(id: message.id.to_s, text: 'hello')
    end
  end
end
