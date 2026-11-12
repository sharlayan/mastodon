# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatDiceBackfill do
  let(:owner) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |conversation|
      conversation.memberships.create!(account: owner, role: :owner)
      conversation.memberships.create!(account: bob)
    end
  end
  let(:dice) { { 'version' => 1, 'engine' => '@dice-roller/rpg-dice-roller', 'engineVersion' => '5.5.1', 'notation' => '1d20', 'total' => 17, 'output' => '1d20: [17] = 17' } }

  def remote_message(id, text)
    room.messages.create!(account: bob, text: text, uri: "https://remote.test/chat/messages/#{id}")
  end

  def stub_note(id, **overrides)
    note = { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "https://remote.test/chat/messages/#{id}", 'type' => 'Note', 'attributedTo' => bob.uri, '_misskey_dice' => dice }
    stub_request(:get, note['id']).to_return(status: 200, headers: { 'Content-Type' => 'application/activity+json' }, body: note.merge(overrides).to_json)
  end

  it 'fills in results fetched with a member signature and leaves everything that does not match alone' do
    filled = remote_message(1, '/dice 1d20')
    other_notation = remote_message(2, '/dice 2d6')
    wrong_author = remote_message(3, '/dice 1d20')
    tampered = remote_message(4, '/dice 1d20')
    remote_message(5, 'just text')
    local = room.messages.create!(account: owner, text: '/dice 1d20', uri: 'https://local.test/chat/messages/6')
    deleted = remote_message(7, '/dice 1d20').tap { |message| message.update_columns(text: nil, deleted_at: Time.current) }
    stub_note(1)
    stub_note(2)
    stub_note(3, 'attributedTo' => 'https://remote.test/users/mallory')
    stub_note(4, '_misskey_dice' => dice.merge('extra' => true))

    expect(described_class.new.call).to eq 1

    expect(filled.reload.dice).to eq dice
    expect([other_notation, wrong_author, tampered, local, deleted].map { |message| message.reload.dice }).to all(be_nil)
    expect(a_request(:get, 'https://remote.test/chat/messages/1').with { |request| request.headers['Signature'].to_s.include?(ActivityPub::TagManager.instance.key_uri_for(owner)) }).to have_been_made
    expect(a_request(:get, 'https://remote.test/chat/messages/5')).to_not have_been_made
    expect(described_class.new.call).to eq 0
  end
end
