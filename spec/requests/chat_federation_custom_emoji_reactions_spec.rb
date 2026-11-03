# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation custom emoji reactions' do
  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:remote) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone')
  end
  let(:stranger) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/eve', inbox_url: 'https://remote.test/users/eve/inbox') }
  let(:conversation) { service.create_conversation(owner, type: :direct, account_ids: [remote.id]) }
  let(:message) { service.create_message(owner, conversation, text: 'react to this') }
  let(:image_url) { 'https://remote.test/emoji/wave.png' }
  let(:emoji_tag) do
    { 'type' => 'Emoji', 'id' => 'https://remote.test/emojis/wave', 'name' => ':wave:', 'icon' => { 'type' => 'Image', 'url' => image_url } }
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    message.update!(uri: Sharlayan::ChatFederation::Payload.message_uri(message))
    stub_request(:get, image_url)
      .to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read, headers: { 'Content-Type' => 'image/png' })
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def reaction_json(actor, tag: [emoji_tag])
    {
      'type' => 'EmojiReact',
      'id' => "#{actor.uri}/chat-reactions/1",
      'actor' => actor.uri,
      'object' => message.uri,
      'content' => ':wave:',
      '_misskey_reaction' => ':wave:',
      'tag' => tag,
    }
  end

  def perform(json, actor)
    ActivityPub::Activity.factory(json, actor, delivered_to_account_id: owner.id).perform
  end

  describe 'receiving' do
    it 'stores the reaction with the image from its tag and removes it on Undo' do
      perform(reaction_json(remote), remote)

      reaction = message.reactions.find_by!(account: remote, reaction: ':wave:')
      emoji = CustomEmoji.find_by!(shortcode: 'wave', domain: 'remote.test')
      expect(emoji.image_remote_url).to eq(image_url)

      json = REST::ChatMessageReactionSerializer.new(reaction).as_json
      expect(json).to include(domain: 'remote.test')
      expect(json[:url]).to be_present

      perform({ 'type' => 'Undo', 'actor' => remote.uri, 'object' => reaction_json(remote) }, remote)
      expect(message.reactions.reload).to be_empty
    end

    it 'does not show a local emoji that happens to share the remote shortcode' do
      local_emoji = Fabricate(:custom_emoji, shortcode: 'wave', domain: nil)
      perform(reaction_json(remote, tag: []), remote)

      reaction = message.reactions.find_by!(account: remote, reaction: ':wave:')
      expect(reaction.custom_emoji).to be_nil
      expect(REST::ChatMessageReactionSerializer.new(reaction).as_json).to_not have_key(:url)
      expect(local_emoji.reload).to be_present
    end

    it 'does not fetch the image for an actor who is not in the conversation' do
      perform(reaction_json(stranger), stranger)

      expect(a_request(:get, image_url)).to_not have_been_made
      expect(CustomEmoji.find_by(shortcode: 'wave', domain: 'remote.test')).to be_nil
      expect(message.reactions.reload).to be_empty
    end

    it 'keeps the reaction but does not fetch the image from a domain whose media is rejected' do
      Fabricate(:domain_block, domain: 'remote.test', severity: :noop, reject_media: true)
      perform(reaction_json(remote), remote)

      expect(a_request(:get, image_url)).to_not have_been_made
      expect(message.reactions.find_by(account: remote, reaction: ':wave:')).to be_present
    end
  end

  describe 'sending' do
    let(:payload) { Sharlayan::ChatFederation::Payload }

    it 'sends the unqualified name with an Emoji tag, on the reaction and on its Undo' do
      emoji = Fabricate(:custom_emoji, shortcode: 'wave', domain: nil)

      react = payload.reaction(message, owner, ':wave:')
      undo = payload.undo_reaction(message, owner, ':wave:')

      expect(react).to include('content' => ':wave:', '_misskey_reaction' => ':wave:')
      expect(react['tag']).to contain_exactly(include('type' => 'Emoji', 'name' => ':wave:', 'icon' => include('url' => be_present), 'id' => ActivityPub::TagManager.instance.uri_for(emoji)))
      expect(undo['object']['tag']).to eq(react['tag'])
      expect(JSON.parse(react.to_json)['tag'].first['type']).to eq('Emoji')
      expect(react['@context'].last).to include('Emoji' => 'toot:Emoji')
    end

    it 'does not attach local-only, disabled, or remote emoji, or unicode reactions' do
      Fabricate(:custom_emoji, shortcode: 'secret', domain: nil, local_only: true)
      Fabricate(:custom_emoji, shortcode: 'off', domain: nil, disabled: true)
      Fabricate(:custom_emoji, shortcode: 'elsewhere', domain: 'remote.test')

      [':secret:', ':off:', ':elsewhere:', '🎉'].each do |reaction|
        expect(payload.reaction(message, owner, reaction)).to_not have_key('tag')
      end
    end
  end
end
