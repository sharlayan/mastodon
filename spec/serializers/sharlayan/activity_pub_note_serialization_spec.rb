# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ActivityPubNoteSerialization do
  subject(:serialized) do
    serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter, options: serializer_options)
  end

  let(:serializer_options) { {} }
  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: account, visibility: :public, text: 'Plain text') }

  context 'with a limited status' do
    let(:status) { Fabricate(:status, account: account, visibility: :limited, limited_scope: :circle) }

    it 'serializes its limited scope and context' do
      expect(serialized)
        .to include('limitedScope' => 'Circle')
        .and include('@context' => include(a_hash_including('limitedScope')))
    end
  end

  context 'with a public status without Sharlayan content' do
    it 'keeps the default content and audience' do
      expect(serialized).to include(
        'content' => '<p>Plain text</p>',
        'to' => include(ActivityPub::TagManager::COLLECTIONS[:public])
      )
      expect(serialized).to_not have_key('limitedScope')
      expect(serialized).to_not have_key('_misskey_content')
    end
  end

  context 'when promoted to public' do
    let(:serializer_options) { { promote_to_public: true } }
    let(:status) { Fabricate(:status, account: account, visibility: :unlisted) }

    it 'swaps the original to and cc audiences' do
      default_serialized = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)

      expect(serialized['to']).to eq(default_serialized['cc'])
      expect(serialized['cc']).to eq(default_serialized['to'])
    end
  end
end
