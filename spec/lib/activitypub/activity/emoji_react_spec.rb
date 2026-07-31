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
  end
end
