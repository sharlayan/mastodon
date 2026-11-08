# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::UserSettingsExtensions do
  let(:user) { Fabricate(:user) }
  let(:stranger) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/stranger', inbox_url: 'https://remote.test/users/stranger/inbox') }

  it 'lets only mutual followers start a chat' do
    expect(user.settings[:chat_policy]).to eq('mutual')
  end

  it 'advertises the same scope to other servers' do
    expect(ActivityPub::ActorSerializer.new(user.account).misskey_chat_scope).to eq('mutual')
  end

  it 'turns away a direct message from a stranger' do
    expect { Sharlayan::ChatService.new.receive_direct_message(user.account, stranger, uri: 'https://remote.test/chat/messages/1', text: 'hi') }
      .to raise_error(Sharlayan::ChatService::Forbidden)
  end

  it 'lets a mutual follower start one' do
    user.account.follow!(stranger)
    stranger.follow!(user.account)

    expect { Sharlayan::ChatService.new.receive_direct_message(user.account, stranger, uri: 'https://remote.test/chat/messages/1', text: 'hi') }
      .to change(ChatMessage, :count).by(1)
  end
end
