# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::NoteSerializer do
  subject { serialized_record_json(parent, described_class, adapter: ActivityPub::Adapter) }

  let!(:account) { Fabricate(:account) }
  let!(:other) { Fabricate(:account) }
  let!(:parent) { Fabricate(:status, account: account, visibility: :public, language: 'zh-TW') }
  let!(:reply_by_account_first) { Fabricate(:status, account: account, thread: parent, visibility: :public) }
  let!(:reply_by_account_next) { Fabricate(:status, account: account, thread: parent, visibility: :public) }
  let!(:reply_by_other_first) { Fabricate(:status, account: other, thread: parent, visibility: :public) }
  let!(:reply_by_account_third) { Fabricate(:status, account: account, thread: parent, visibility: :public) }
  let!(:reply_by_account_visibility_direct) { Fabricate(:status, account: account, thread: parent, visibility: :direct) }

  it 'has the expected shape and replies collection' do
    expect(subject).to include({
      '@context' => include('https://www.w3.org/ns/activitystreams'),
      'type' => 'Note',
      'attributedTo' => ActivityPub::TagManager.instance.uri_for(account),
      'contentMap' => include({
        'zh-TW' => a_kind_of(String),
      }),
      'replies' => replies_collection_values,
      'context' => ActivityPub::TagManager.instance.uri_for(parent.conversation),
    })
  end

  def replies_collection_values
    include(
      'type' => eql('Collection'),
      'first' => include(
        'type' => eql('CollectionPage'),
        'items' => reply_items
      )
    )
  end

  def reply_items
    include(reply_by_account_first.uri, reply_by_account_next.uri, reply_by_account_third.uri) # Public self replies
      .and(not_include(reply_by_other_first.uri)) # Replies from others
      .and(not_include(reply_by_account_visibility_direct.uri)) # Replies with direct visibility
  end

  context 'with tagged featured collections' do
    let(:collection) { Fabricate(:collection) }

    before do
      parent.tagged_objects.create!(object: collection, ap_type: 'FeaturedCollection', uri: ActivityPub::TagManager.instance.uri_for(collection))
    end

    it 'has the expected shape' do
      expect(subject).to include({
        'type' => 'Note',
        'tag' => include(
          a_hash_including({
            'type' => 'FeaturedCollection',
            'id' => ActivityPub::TagManager.instance.uri_for(collection),
          })
        ),
      })
    end
  end

  context 'with a quote' do
    let(:quoted_status) { Fabricate(:status) }
    let!(:quote) { Fabricate(:quote, status: parent, quoted_status: quoted_status, state: :accepted) }

    it 'has the expected shape' do
      expect(subject).to include({
        'type' => 'Note',
        'quote' => ActivityPub::TagManager.instance.uri_for(quote.quoted_status),
        'quoteUri' => ActivityPub::TagManager.instance.uri_for(quote.quoted_status),
        '_misskey_quote' => ActivityPub::TagManager.instance.uri_for(quote.quoted_status),
        'quoteAuthorization' => ActivityPub::TagManager.instance.approval_uri_for(quote),
      })
    end
  end

  context 'with a deleted quote' do
    let(:quoted_status) { Fabricate(:status) }

    before do
      Fabricate(:quote, status: parent, quoted_status: nil, state: :accepted)
    end

    it 'has the expected shape' do
      expect(subject).to include({
        'type' => 'Note',
        'quote' => { 'type' => 'Tombstone' },
      })
    end
  end

  context 'with a local MFM post' do
    let!(:local_account) { Fabricate(:account, domain: nil) }
    let!(:parent) { Fabricate(:status, account: local_account, text: '$[tada hello world]', mfm: true, visibility: :public, language: 'en') }

    it 'includes _misskey_content with the raw MFM text' do
      expect(subject).to include('_misskey_content' => '$[tada hello world]')
    end

    it 'includes source with misskeymarkdown mediaType' do
      expect(subject).to include(
        'source' => {
          'content' => '$[tada hello world]',
          'mediaType' => 'text/x.misskeymarkdown',
        }
      )
    end

    it 'has content as HTML (not raw MFM)' do
      expect(subject['content']).to be_a(String)
      expect(subject['content']).to_not start_with('$[')
    end
  end

  context 'with a non-MFM local post' do
    it 'does not include _misskey_content' do
      expect(subject).to_not have_key('_misskey_content')
    end

    it 'does not include source with misskeymarkdown mediaType' do
      source = subject['source']
      expect(source).to be_nil.or(
        satisfy { |s| s.is_a?(Hash) && s['mediaType'] != 'text/x.misskeymarkdown' }
      )
    end
  end

  context 'with a remote MFM post' do
    let!(:remote_account) { Fabricate(:account, domain: 'remote.example', uri: 'https://remote.example/users/1') }
    let!(:parent) { Fabricate(:status, account: remote_account, text: '$[tada hello]', mfm: true, visibility: :public, language: 'en', uri: 'https://remote.example/statuses/1') }

    it 'does not include _misskey_content' do
      expect(subject).to_not have_key('_misskey_content')
    end
  end

  context 'with a quote policy' do
    let(:parent) { Fabricate(:status, quote_approval_policy: InteractionPolicy::POLICY_FLAGS[:followers] << 16) }

    it 'has the expected shape' do
      expect(subject).to include({
        'type' => 'Note',
        'interactionPolicy' => a_hash_including(
          'canQuote' => a_hash_including(
            'automaticApproval' => [ActivityPub::TagManager.instance.followers_uri_for(parent.account)]
          )
        ),
      })
    end
  end

  context 'with a preview card' do
    let(:preview_card) { Fabricate(:preview_card) }

    before do
      PreviewCardsStatus.create(status: parent, preview_card: preview_card)
    end

    it 'has the expected shape (using FEP-8967)' do
      expect(subject).to include({
        'type' => 'Note',
        'attachment' => contain_exactly(
          a_hash_including(
            'href' => preview_card.url
          )
        ),
      })
    end
  end
end
