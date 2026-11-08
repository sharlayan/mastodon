# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::EmojiReact do
  let(:sender) { Fabricate(:account) }
  let(:remote_sender) { Fabricate(:account, domain: 'example.com') }
  let(:recipient) { Fabricate(:account) }
  let(:status)    { Fabricate(:status, account: recipient) }
  let(:custom_emoji) { Fabricate(:custom_emoji) }
  let(:remote_custom_emoji) { Fabricate(:custom_emoji, domain: 'example.com') }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'EmojiReact',
      content: '👍',
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  let(:custom_emoji_icon_url) { 'https://example.com/emoji.png' }

  let(:json_custom_emoji) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'EmojiReact',
      content: ":#{custom_emoji.shortcode}:",
      tag: [
        {
          type: 'Emoji',
          name: ":#{custom_emoji.shortcode}:",
          icon: { type: 'Image', url: custom_emoji_icon_url },
        },
      ],
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  let(:json_remote_custom_emoji) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'EmojiReact',
      content: ":#{remote_custom_emoji.shortcode}:",
      tag: [
        {
          type: 'Emoji',
          name: ":#{remote_custom_emoji.shortcode}:",
          icon: { type: 'Image', url: custom_emoji_icon_url },
        },
      ],
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  before do
    stub_request(:get, custom_emoji_icon_url)
      .to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read, headers: { 'Content-Type' => 'image/png' })
  end

  describe '#perform' do
    context 'with an emoji' do
      subject { described_class.new(json, sender) }

      before do
        subject.perform
      end

      it 'creates a reaction from sender to status' do
        expect(sender.reacted?(status, '👍')).to be true
      end
    end

    context 'with a custom emoji' do
      subject { described_class.new(json_custom_emoji, sender) }

      before do
        subject.perform
      end

      it 'creates a reaction from sender to status' do
        expect(sender.reacted?(status, custom_emoji.shortcode, custom_emoji)).to be true
      end
    end

    context 'with a remote custom emoji' do
      subject { described_class.new(json_remote_custom_emoji, remote_sender) }

      before do
        subject.perform
      end

      it 'creates a reaction from sender to status' do
        expect(remote_sender.reacted?(status, remote_custom_emoji.shortcode, remote_custom_emoji)).to be true
      end
    end

    context 'with a new custom emoji from a domain whose media is rejected' do
      subject { described_class.new(json_new_remote_emoji, remote_sender) }

      let(:json_new_remote_emoji) do
        json_remote_custom_emoji.merge(
          content: ':fresh:',
          tag: [{ type: 'Emoji', name: ':fresh:', icon: { type: 'Image', url: 'https://example.com/fresh.png' } }]
        )
      end

      before do
        Fabricate(:domain_block, domain: 'example.com', severity: :noop, reject_media: true)
        stub_request(:get, 'https://example.com/fresh.png').to_return(status: 200, body: attachment_fixture('emojo.png'))
        subject.perform
      end

      it 'does not create or download the emoji' do
        expect(CustomEmoji.exists?(shortcode: 'fresh', domain: 'example.com')).to be false
        expect(a_request(:get, 'https://example.com/fresh.png')).to_not have_been_made
      end
    end

    context 'with a sensitive remote custom emoji that the status excludes' do
      subject { described_class.new(json_remote_custom_emoji, remote_sender) }

      before do
        status.update!(reaction_acceptance: 'nonSensitiveOnly')
        json_remote_custom_emoji[:tag].first[:isSensitive] = true
        subject.perform
      end

      it 'stores the remote sensitivity and normalizes the reaction to a like' do
        expect(remote_custom_emoji.reload).to be_is_sensitive
        expect(remote_sender.reacted?(status, "\u2764")).to be true
      end
    end

    context 'when the object is a boost of a status whose author mutes the sender' do
      subject { described_class.new(json.merge(object: ActivityPub::TagManager.instance.uri_for(boost)), sender) }

      let(:boost) { Fabricate(:status, account: Fabricate(:account, domain: 'booster.example'), uri: 'https://booster.example/notes/boost', reblog: status) }

      before do
        ReactionMute.create!(account: recipient, target_account: sender)
        subject.perform
      end

      it 'does not create a reaction' do
        expect(status.status_reactions).to be_empty
      end
    end

    context 'when the object is a boost' do
      subject { described_class.new(json.merge(object: ActivityPub::TagManager.instance.uri_for(boost)), sender) }

      let(:boost) { Fabricate(:status, account: Fabricate(:account, domain: 'booster.example'), uri: 'https://booster.example/notes/boost', reblog: status) }

      before do
        allow(LocalNotificationWorker).to receive(:perform_async)
        subject.perform
      end

      it 'notifies the original author' do
        reaction = status.status_reactions.find_by!(account: sender)

        expect(LocalNotificationWorker).to have_received(:perform_async).with(recipient.id, reaction.id, 'StatusReaction', 'reaction')
      end
    end
  end
end
