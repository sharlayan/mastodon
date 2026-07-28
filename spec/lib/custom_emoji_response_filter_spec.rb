# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmojiResponseFilter do
  let(:rules) do
    [
      { 'prefix' => 'mute', 'domain' => '' },
      { 'prefix' => 'remote', 'domain' => 'example.com' },
    ]
  end

  it 'replaces muted REST emoji shortcodes and removes their metadata' do
    payload = {
      content: '<p>Hello :muted_blob: and :visible:</p>',
      emojis: [
        { shortcode: 'muted_blob', url: 'https://local/muted.gif' },
        { shortcode: 'visible', url: 'https://local/visible.gif' },
      ],
      account: {
        display_name: ':muted_blob: Person',
        fields: [{ name: 'Field', value: ':muted_blob:' }],
      },
    }

    result = described_class.filter(payload, rules)

    expect(result[:content]).to eq('<p>Hello ⬛ and :visible:</p>')
    expect(result[:emojis]).to contain_exactly(hash_including(shortcode: 'visible'))
    expect(result.dig(:account, :display_name)).to eq('⬛ Person')
    expect(result.dig(:account, :fields, 0, :value)).to eq('⬛')
  end

  it 'keeps a domain-specific mute from matching another domain' do
    payload = {
      content: '<p>:remote_face: :remote_other:</p>',
      emojis: [
        { shortcode: 'remote_face', domain: 'example.com', url: 'https://example.com/face.gif' },
        { shortcode: 'remote_other', domain: 'elsewhere.example', url: 'https://elsewhere.example/other.gif' },
      ],
    }

    result = described_class.filter(payload, rules)

    expect(result[:content]).to eq('<p>⬛ :remote_other:</p>')
    expect(result[:emojis]).to contain_exactly(hash_including(shortcode: 'remote_other'))
  end

  it 'removes muted REST reactions instead of replacing them' do
    payload = {
      reactions: [
        { name: 'muted_reaction', domain: '', url: 'https://local/muted.gif', count: 2 },
        { name: '👍', count: 1 },
        { name: 'visible', domain: '', url: 'https://local/visible.gif', count: 3 },
      ],
    }

    result = described_class.filter(payload, rules)

    expect(result[:reactions]).to contain_exactly(
      hash_including(name: '👍'),
      hash_including(name: 'visible')
    )
  end

  it 'filters Misskey emoji maps and custom reaction maps' do
    payload = {
      text: ':muted_note: :visible:',
      emojis: { 'muted_note' => 'muted-url', 'visible' => 'visible-url' },
      reactions: { ':muted_reaction@.:' => 2, ':visible@.:' => 1, '👍' => 3 },
      reactionEmojis: { 'muted_reaction@.' => 'muted-url', 'visible@.' => 'visible-url' },
      myReaction: ':muted_reaction@.:',
    }

    result = described_class.filter(payload, rules)

    expect(result[:text]).to eq('⬛ :visible:')
    expect(result[:emojis]).to eq('visible' => 'visible-url')
    expect(result[:reactions]).to eq(':visible@.:' => 1, '👍' => 3)
    expect(result[:reactionEmojis]).to eq('visible@.' => 'visible-url')
    expect(result[:myReaction]).to be_nil
  end

  it 'removes muted reaction notifications from response lists' do
    payload = [
      { type: 'reaction', reaction: { name: 'muted_reaction', domain: '', url: 'muted-url' } },
      { type: 'mention', account: { display_name: 'Person' } },
    ]

    expect(described_class.filter(payload, rules)).to contain_exactly(hash_including(type: 'mention'))
  end
end
