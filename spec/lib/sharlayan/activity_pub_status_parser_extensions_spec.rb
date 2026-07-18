# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ActivityPubStatusParserExtensions do
  subject(:parser) do
    ActivityPub::Parser::StatusParser.new(
      json,
      actor_uri: actor_uri,
      followers_collection: followers_collection
    )
  end

  let(:actor_uri) { 'https://misskey.example/users/alice' }
  let(:followers_collection) { 'https://misskey.example/users/alice/followers' }
  let(:context) { ['https://www.w3.org/ns/activitystreams'] }
  let(:visibility_target) { ActivityPub::TagManager::COLLECTIONS[:public] }
  let(:object) do
    {
      'id' => 'https://misskey.example/notes/1',
      'type' => 'Note',
      'to' => visibility_target,
      'content' => 'plain content',
    }
  end
  let(:json) do
    {
      '@context' => context,
      'actor' => actor_uri,
      'object' => object,
    }
  end

  context 'with a Misskey context' do
    let(:context) do
      [
        'https://www.w3.org/ns/activitystreams',
        { 'misskey' => 'https://misskey-hub.net/ns#' },
      ]
    end

    it 'recognizes the server and grants public notes follower auto-approval' do
      expect(parser).to be_from_misskey
      expect(parser.quote_policy).to eq(InteractionPolicy::POLICY_FLAGS[:followers] << 16)
    end

    it 'removes only the synthetic break before an inline quote' do
      object['content'] = 'body<br/><span class="quote-inline">quote</span><br/>tail'

      expect(parser.text).to eq('body<span class="quote-inline">quote</span><br/>tail')
    end

    context 'with a private note' do
      let(:visibility_target) { followers_collection }

      it 'keeps the default quote policy' do
        expect(parser.quote_policy).to eq(0)
      end
    end
  end

  context 'with a limited scope URI' do
    before { object['limitedScope'] = 'Mutual' }

    it 'maps the URI value to the status enum' do
      expect(parser.limited_scope).to eq('mutual')
    end
  end

  context 'without a Misskey context' do
    it 'keeps content unchanged and does not claim Misskey origin' do
      object['content'] = 'body<br/><span class="quote-inline">quote</span>'

      expect(parser).to_not be_from_misskey
      expect(parser.text).to eq('body<br/><span class="quote-inline">quote</span>')
    end
  end
end
