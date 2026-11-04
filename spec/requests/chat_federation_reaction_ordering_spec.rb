# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation reaction ordering' do
  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:user) { Fabricate(:user) }
  let(:owner) { user.account }
  let(:actor) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:other) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/carol', inbox_url: 'https://remote.test/users/carol/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:conversation) do
    service.create_conversation(owner, type: :group, title: 'Room').tap do |room|
      room.memberships.create!(account: actor)
      room.memberships.create!(account: other)
    end
  end
  let(:message) { service.create_message(owner, conversation, text: 'hello') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def react(id, target: message.uri, account: actor, content: '👍', **extra)
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "https://remote.test/chat-reactions/#{id}",
      'type' => 'EmojiReact',
      'actor' => account.uri,
      'object' => target,
      'content' => content,
    }.merge(extra.stringify_keys)
  end

  def undo(reaction, account: actor)
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "#{reaction['id']}/undo",
      'type' => 'Undo',
      'actor' => account.uri,
      'object' => reaction,
    }
  end

  def perform(json, account: actor)
    ActivityPub::ProcessingWorker.new.perform(account.id, json.to_json, owner.id)
  end

  it 'gives each new local reaction its own activity ID and undoes the same ID' do
    remote_message = service.receive_group_message(actor, room_uri: conversation.uri, uri: 'https://remote.test/chat/messages/outgoing', text: 'remote')
    ActivityPub::DeliveryWorker.clear

    service.react(owner, remote_message, '👍')
    service.unreact(owner, remote_message, '👍')
    service.react(owner, remote_message, '👍')

    activities = ActivityPub::DeliveryWorker.jobs.filter_map do |job|
      JSON.parse(job['args'].first) if job['args'][2] == actor.inbox_url
    end
    first, removed, second = activities
    expect(first['type']).to eq('EmojiReact')
    expect(removed.dig('object', 'id')).to eq(first['id'])
    expect(second['type']).to eq('EmojiReact')
    expect(second['id']).to_not eq(first['id'])
  end

  it 'rejects local self-reactions through the API' do
    post "/api/v1/chat/messages/#{message.id}/reactions", params: { reaction: '👍' }, headers: headers

    expect(response).to have_http_status(403)
    expect(message.reactions.reload).to be_empty
  end

  it 'does not resurrect a reaction whose Undo arrived first' do
    reaction = react('cancelled')
    perform(undo(reaction))
    perform(reaction)

    expect(message.reactions.reload).to be_empty
  end

  it 'does not let a delayed old Undo remove a new reaction cycle' do
    first = react('first')
    second = react('second')
    perform(first)
    perform(undo(first))
    perform(second)
    perform(undo(first))

    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
    perform(undo(second))
    expect(message.reactions.reload).to be_empty
  end

  it 'keeps another active ID when a new React overtakes an old Undo' do
    first = react('first')
    second = react('second')
    perform(first)
    perform(second)
    perform(undo(first))

    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
    perform(undo(second))
    expect(message.reactions.reload).to be_empty
  end

  it 'scopes cancelled IDs to the verified actor' do
    perform(undo(react('shared')))
    perform(react('shared', account: other), account: other)

    expect(message.reactions.reload.pluck(:account_id)).to eq([other.id])
  end

  it 'rejects an Undo whose embedded actor is different from the signer' do
    reaction = react('first')
    perform(reaction)
    perform(undo(reaction.merge('actor' => other.uri)))

    expect(message.reactions.reload.pluck(:account_id)).to eq([actor.id])
  end

  it 'expires cancellation state after the six-hour replay window' do
    reaction = react('expired')
    perform(undo(reaction))
    travel 6.hours - 1.second
    perform(reaction)
    expect(message.reactions.reload).to be_empty

    travel 2.seconds
    perform(reaction)
    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'bounds the active IDs retained for one visible reaction' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTIVE_IDS', 2)
    first = react('first')
    second = react('second')
    perform(first)
    perform(second)
    perform(react('overflow'))
    perform(undo(first))
    perform(undo(second))

    expect(message.reactions.reload).to be_empty
  end

  it 'bounds active IDs across messages from an actor and frees capacity on Undo' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 2)
    second_message = service.create_message(owner, conversation, text: 'second')
    third_message = service.create_message(owner, conversation, text: 'third')
    first = react('first')
    second = react('second', target: second_message.uri)
    third = react('third', target: third_message.uri)
    perform(first)
    perform(first)
    perform(second)
    perform(third)

    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
    expect(second_message.reactions.reload.pluck(:reaction)).to eq(['👍'])
    expect(third_message.reactions.reload).to be_empty

    perform(undo(first))
    perform(third)
    expect(third_message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'keeps active ID quotas separate for each actor' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 1)
    perform(react('first'))
    perform(react('second', account: other), account: other)

    expect(message.reactions.reload.pluck(:account_id)).to contain_exactly(actor.id, other.id)
  end

  it 'does not store a reaction if actor capacity is consumed during emoji import' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 1)
    other_message = service.create_message(owner, conversation, text: 'other')
    competing_state = Sharlayan::ChatFederation::ReactionState.new(actor, other_message, '👍')

    expect do
      service.react_remote(actor, message, ':wave:', activity_id: 'https://remote.test/chat-reactions/loser') do
        competing_state.add('https://remote.test/chat-reactions/winner')
      end
    end.to_not raise_error

    expect(message.reactions.reload).to be_empty
  end

  it 'releases actor capacity when an id-less Undo clears a tracked reaction' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 1)
    second_message = service.create_message(owner, conversation, text: 'second')
    first = react('first')
    perform(first)
    perform(undo(first.except('id')))
    perform(react('second', target: second_message.uri))

    expect(message.reactions.reload).to be_empty
    expect(second_message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'keeps the newest cancellations when one actor exceeds the retained ID limit' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_CANCELLED_IDS', 2)
    first = react('first')
    second = react('second')
    third = react('third')
    perform(undo(first))
    travel 1.second
    perform(undo(second))
    travel 1.second
    perform(undo(third))
    perform(second)
    perform(third)
    expect(message.reactions.reload).to be_empty

    perform(first)
    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'rejects malformed and off-origin reaction IDs without changing replay state' do
    ['', 'https://unrelated.test/reactions/1', 'ftp://remote.test/reactions/1', "https://remote.test/#{'a' * 2048}", { 'id' => 'https://remote.test/reactions/1' }].each do |id|
      perform(react('invalid').merge('id' => id))
    end

    expect(message.reactions.reload).to be_empty
    perform(react('valid'))
    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'does not route a missing target to an unrelated message without a URI' do
    unaddressed = conversation.messages.create!(account: owner, text: 'no federation URI')

    perform(react('missing-target', target: nil))

    expect(unaddressed.reactions.reload).to be_empty
  end

  it 'retries a reaction that overtook Create and applies it once the message arrives' do
    target = 'https://remote.test/chat/messages/pending'
    conversation
    reaction = react('pending', target: target)

    expect { perform(reaction) }.to raise_error(StandardError, 'Chat message has not arrived')
    received = service.receive_group_message(other, room_uri: conversation.uri, uri: target, text: 'later')
    perform(reaction)
    perform(reaction)

    expect(received.reactions.reload.pluck(:account_id, :reaction)).to eq([[actor.id, '👍']])
  end

  it 'retries an Undo that overtook Create and still cancels its delayed React' do
    target = 'https://remote.test/chat/messages/pending-undo'
    conversation
    reaction = react('pending-undo', target: target)

    expect { perform(undo(reaction)) }.to raise_error(StandardError, 'Chat message has not arrived')
    received = service.receive_group_message(other, room_uri: conversation.uri, uri: target, text: 'later')
    perform(undo(reaction))
    perform(reaction)

    expect(received.reactions.reload).to be_empty
  end

  it 'retries a group reaction that overtook the reactor membership' do
    reaction = react('before-membership')
    conversation.memberships.find_by!(account: actor).destroy!
    conversation.invitations.create!(inviter_account: owner, invitee_account: actor)

    expect { perform(reaction) }.to raise_error(StandardError, 'Waiting for chat membership')
    expect(message.reactions.reload).to be_empty
    service.receive_accept(actor, room_uri: conversation.uri)
    perform(reaction)

    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])
  end

  it 'does not retry a group reaction from someone with no invitation to the room' do
    reaction = react('stranger')
    conversation.memberships.find_by!(account: actor).destroy!

    expect { perform(reaction) }.to_not raise_error
    expect(message.reactions.reload).to be_empty
  end

  it 'lets a former member take back a reaction' do
    reaction = react('undo-after-leaving')
    perform(reaction)
    conversation.memberships.find_by!(account: actor).destroy!

    perform(undo(reaction))

    expect(message.reactions.reload).to be_empty
  end

  it 'retries a group Undo from someone who has yet to join' do
    reaction = react('undo-before-membership')
    stranger = Fabricate(:account, domain: 'stranger.test', uri: 'https://stranger.test/users/dave', inbox_url: 'https://stranger.test/users/dave/inbox')
    conversation.invitations.create!(inviter_account: owner, invitee_account: stranger)
    foreign = reaction.merge('id' => 'https://stranger.test/chat-reactions/1', 'actor' => stranger.uri)

    expect { ActivityPub::Activity.factory(undo(foreign, account: stranger), stranger).perform }.to raise_error(StandardError, 'Waiting for chat membership')
  end

  it 'rechecks membership on retry before importing a custom emoji' do
    target = 'https://remote.test/chat/messages/pending-private'
    image_url = 'https://remote.test/emoji/wave.png'
    conversation
    reaction = react('pending-private', target: target, content: ':wave:', tag: [{ type: 'Emoji', name: ':wave:', icon: { type: 'Image', url: image_url } }])

    expect { perform(reaction) }.to raise_error(StandardError, 'Chat message has not arrived')
    received = service.receive_group_message(other, room_uri: conversation.uri, uri: target, text: 'later')
    conversation.memberships.find_by!(account: actor).destroy!
    conversation.invitations.create!(inviter_account: owner, invitee_account: actor)
    expect { perform(reaction) }.to raise_error(StandardError, 'Waiting for chat membership')

    expect(received.reactions.reload).to be_empty
    expect(a_request(:get, image_url)).to_not have_been_made
  end
end
