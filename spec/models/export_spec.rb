# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Export do
  subject { described_class.new(account) }

  let(:account) { Fabricate(:account) }
  let(:target_accounts) do
    [
      Fabricate(:account),
      Fabricate(:account, username: 'one', domain: 'local.host'),
    ]
  end

  describe '#to_bookmarks_csv' do
    let!(:bookmark) { Fabricate(:bookmark, account: account) }
    let(:export) { CSV.parse(subject.to_bookmarks_csv) }
    let!(:second_bookmark) { Fabricate(:bookmark, account: account) }
    let!(:bookmark_of_soft_deleted) { Fabricate(:bookmark, account: account) }

    before do
      bookmark_of_soft_deleted.status.discard
    end

    it 'returns a csv of bookmarks' do
      expect(export)
        .to contain_exactly(
          [ActivityPub::TagManager.instance.uri_for(bookmark.status)],
          [ActivityPub::TagManager.instance.uri_for(second_bookmark.status)]
        )
    end
  end

  describe '#to_clips_json' do
    before { stub_const('Clip::STATUSES_LIMIT', 1) }

    it 'bounds statuses from legacy clips that exceed the current limit' do
      clip = Fabricate(:clip, account: account)
      older_status = Fabricate(:status)
      newer_status = Fabricate(:status)
      clip.clip_statuses.create!(status: older_status)
      ClipStatus.insert_all!([{ clip_id: clip.id, status_id: newer_status.id, created_at: Time.current, updated_at: Time.current }])

      exported = JSON.parse(subject.to_clips_json)

      expect(exported.dig('clips', 0, 'statuses')).to contain_exactly(ActivityPub::TagManager.instance.uri_for(newer_status))
    end
  end

  describe '#to_chat_json' do
    let(:other_account) { Fabricate(:account) }
    let(:hidden_account) { Fabricate(:account) }

    it 'exports only conversations the account belongs to with messages and reactions' do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [account.id, other_account.id].sort.join(':'))
      conversation.memberships.create!([{ account: account }, { account: other_account }])
      message = conversation.messages.create!(account: other_account, text: 'hello')
      message.reactions.create!(account: account, reaction: '👍')
      hidden_conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [other_account.id, hidden_account.id].sort.join(':'))
      hidden_conversation.memberships.create!([{ account: other_account }, { account: hidden_account }])
      hidden_conversation.messages.create!(account: hidden_account, text: 'private')

      exported = JSON.parse(subject.to_chat_json)

      expect(exported['chat_conversations'].pluck('id')).to contain_exactly(conversation.id.to_s)
      expect(exported.dig('chat_conversations', 0, 'participants')).to contain_exactly(account.local_username_and_domain, other_account.local_username_and_domain)
      expect(exported.dig('chat_conversations', 0, 'messages', 0)).to include(
        'id' => message.id.to_s,
        'sender' => other_account.local_username_and_domain,
        'text' => 'hello',
        'reactions' => [{ 'reaction' => '👍', 'account' => account.local_username_and_domain }]
      )
    end

    it 'does not export the text of deleted messages' do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [account.id, other_account.id].sort.join(':'))
      conversation.memberships.create!([{ account: account }, { account: other_account }])
      conversation.messages.create!(account: account, text: nil, deleted_at: Time.current)

      exported = JSON.parse(subject.to_chat_json)

      expect(exported.dig('chat_conversations', 0, 'messages', 0, 'text')).to be_nil
      expect(exported.dig('chat_conversations', 0, 'messages', 0, 'deleted_at')).to be_present
    end

    it 'does not export messages the sender hid from themselves' do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [account.id, other_account.id].sort.join(':'))
      conversation.memberships.create!([{ account: account }, { account: other_account }])
      conversation.messages.create!(account: account, text: 'hidden', hidden_at: Time.current)
      visible_message = conversation.messages.create!(account: other_account, text: 'visible')

      exported = JSON.parse(subject.to_chat_json)

      expect(exported.dig('chat_conversations', 0, 'messages').pluck('id')).to contain_exactly(visible_message.id.to_s)
    end
  end

  describe '#to_blocked_accounts_csv' do
    before { target_accounts.each { |target_account| account.block!(target_account) } }

    let(:export) { CSV.parse(subject.to_blocked_accounts_csv) }

    it 'returns a csv of the blocked accounts' do
      expect(export)
        .to contain_exactly(
          include('one@local.host'),
          include(be_present)
        )
    end
  end

  describe '#to_muted_accounts_csv' do
    before { target_accounts.each { |target_account| account.mute!(target_account) } }

    let(:export) { CSV.parse(subject.to_muted_accounts_csv) }

    it 'returns a csv of the muted accounts' do
      expect(export)
        .to contain_exactly(
          contain_exactly('Account address', 'Hide notifications'),
          include('one@local.host', 'true'),
          include(be_present)
        )
    end
  end

  describe '#to_following_accounts_csv' do
    before { target_accounts.each { |target_account| account.follow!(target_account) } }

    let(:export) { CSV.parse(subject.to_following_accounts_csv) }

    it 'returns a csv of the following accounts' do
      expect(export)
        .to contain_exactly(
          contain_exactly('Account address', 'Show boosts', 'Notify on new posts', 'Languages'),
          include('one@local.host', 'true', 'false', be_blank),
          include(be_present)
        )
    end
  end

  describe '#to_lists_csv' do
    before do
      target_accounts.each do |target_account|
        account.follow!(target_account)
        Fabricate(:list, account: account).accounts << target_account
      end
    end

    let(:export) { CSV.parse(subject.to_lists_csv) }

    it 'returns a csv of the lists' do
      expect(export)
        .to contain_exactly(
          include('one@local.host'),
          include(be_present)
        )
    end
  end

  describe '#to_blocked_domains_csv' do
    before { Fabricate.times(2, :account_domain_block, account: account) }

    let(:export) { CSV.parse(subject.to_blocked_domains_csv) }

    it 'returns a csv of the blocked domains' do
      expect(export)
        .to contain_exactly(
          include(/example/),
          include(/example/)
        )
    end
  end
end
