# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat write rate limit' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:room) { Sharlayan::ChatService.new.create_conversation(user.account, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    user.role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:bypass_rate_limit])
  end

  after do
    Setting.chat_enabled = false
    Setting.rate_limit_bypass_enabled = false
  end

  def send_message
    post "/api/v1/chat/conversations/#{room.id}/messages", headers: headers, params: { text: 'hello' }
  end

  it 'limits a bypass role while the server does not allow bypassing' do
    Setting.rate_limit_bypass_enabled = false
    limiter = instance_double(RateLimiter)
    allow(RateLimiter).to receive(:new).with(user.account, family: :chat_writes).and_return(limiter)
    allow(limiter).to receive(:record!).and_raise(Mastodon::RateLimitExceededError)

    send_message

    expect(response).to have_http_status(429)
  end

  it 'lets a bypass role through while the server allows bypassing' do
    Setting.rate_limit_bypass_enabled = true
    allow(RateLimiter).to receive(:new).and_call_original

    send_message

    expect(response).to have_http_status(200)
    expect(RateLimiter).to_not have_received(:new).with(user.account, family: :chat_writes)
  end
end
