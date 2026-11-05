# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Acknowledging a streaming subscription', :inline_jobs, :streaming do
  let(:application) { Fabricate(:application, confidential: false) }
  let(:scopes) { 'read' }
  let(:user_account) { Fabricate(:account, username: 'alice', domain: nil) }
  let(:access_token) { Fabricate(:accessible_access_token, resource_owner_id: user_account.user.id, application: application, scopes: scopes) }
  let(:subscribed) { { stream: ['user'], event: 'subscribed' } }

  before do
    streaming_client.authenticate(access_token.token)
    streaming_client.connect
  end

  after do
    streaming_client.close
  end

  def publish_to_user(event, payload)
    redis.publish("timeline:#{user_account.id}", JSON.generate(event: event, payload: JSON.generate(payload)))
  end

  it 'answers a client that asks, without being sent anything else' do
    streaming_client.subscribe('user', ack: true)

    expect(streaming_client.wait_for_message).to eq(subscribed)
    expect(streaming_client.messages.size).to eq(1)
  end

  it 'delivers what is published the moment after it has answered' do
    streaming_client.subscribe('user', ack: true)
    streaming_client.wait_for_message

    publish_to_user('chat.message', { id: '1' })

    expect(streaming_client.wait_for_message).to eq(stream: ['user'], event: 'chat.message', payload: { id: '1' })
  end

  it 'answers again for a channel the connection has already subscribed to' do
    streaming_client.subscribe('user', ack: true)
    streaming_client.wait_for_message

    streaming_client.subscribe('user', ack: true)

    expect(streaming_client.wait_for_message).to eq(subscribed)
  end

  it 'answers a second connection to a channel that Redis is already subscribed to' do
    streaming_client.subscribe('user', ack: true)
    streaming_client.wait_for_message
    other_connection = StreamingClient.new
    other_connection.authenticate(access_token.token)
    other_connection.connect

    other_connection.subscribe('user', ack: true)

    expect(other_connection.wait_for_message).to eq(subscribed)
  ensure
    other_connection&.close
  end

  it 'sends a client that does not ask nothing new' do
    streaming_client.subscribe('user')
    # This answer comes after the first subscription has been dealt with, and only for its own stream.
    streaming_client.subscribe('public:local', ack: true)

    expect(streaming_client.wait_for_message).to eq(stream: ['public:local'], event: 'subscribed')
    expect(streaming_client.messages.size).to eq(1)
  end

  it 'takes only a real true as asking' do
    streaming_client.subscribe('user', ack: 'true')
    streaming_client.subscribe('public:local', ack: true)

    expect(streaming_client.wait_for_message).to eq(stream: ['public:local'], event: 'subscribed')
    expect(streaming_client.messages.size).to eq(1)
  end

  context 'when the access token may not read the channel' do
    let(:scopes) { 'profile' }

    it 'sends the error and no answer' do
      streaming_client.subscribe('user', ack: true)

      expect(streaming_client.wait_for_message).to include(error: 'Access token does not have the required scopes', status: 401)
      expect(streaming_client.messages.size).to eq(1)
    end
  end
end
