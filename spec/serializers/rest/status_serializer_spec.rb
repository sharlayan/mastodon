# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::StatusSerializer do
  subject do
    serialized_record_json(
      status,
      described_class,
      options: {
        scope: current_user,
        scope_name: :current_user,
      }
    )
  end

  let(:current_user) { Fabricate(:user) }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob)   { Fabricate(:account, username: 'bob', domain: 'other.com') }
  let(:status) { Fabricate(:status, account: alice) }

  context 'with a local status' do
    context 'with instance metadata enabled' do
      before do
        allow(Setting).to receive(:[]).and_call_original
        allow(Setting).to receive(:[]).with('instance_metadata_enabled').and_return(true)
      end

      it 'serializes local metadata even when no custom favicon is configured' do
        expect(subject['instance_metadata']).to include(
          'domain' => Rails.configuration.x.local_domain,
          'software' => 'mastodon',
          'favicon_url' => nil
        )
      end
    end

    context 'with a quote and a CW but no contents' do
      let(:quoted_status) { Fabricate(:status, account: alice) }
      let(:status) { Fabricate.build(:status, account: alice, text: '', spoiler_text: 'this is a CW') }

      before do
        Fabricate(:quote, status: status, quoted_status: quoted_status, state: :accepted)
      end

      it 'renders the status with a CW and fallback link' do
        expect(subject)
          .to include(
            'content' => /RE: <a/,
            'spoiler_text' => 'this is a CW'
          )
      end
    end
  end

  context 'with a remote status' do
    let(:status) { Fabricate(:status, account: bob) }

    before do
      status.status_stat.tap do |status_stat|
        status_stat.reblogs_count = 10
        status_stat.favourites_count = 20
        status_stat.quotes_count = 15
        status_stat.save
      end
    end

    context 'with only trusted counts' do
      it 'shows the trusted counts' do
        expect(subject['reblogs_count']).to eq(10)
        expect(subject['favourites_count']).to eq(20)
        expect(subject['quotes_count']).to eq(15)
      end
    end

    context 'with cached instance metadata' do
      before do
        allow(Setting).to receive(:[]).and_call_original
        allow(Setting).to receive(:[]).with('instance_metadata_enabled').and_return(true)
        Fabricate(:instance_metadata, domain: bob.domain, software: 'misskey', metadata_updated_at: Time.current)
        RequestStore.store.delete(:instance_metadata_by_domain)
      end

      it 'serializes the cached metadata without scheduling a refresh' do
        allow(InstanceMetadataUpdateWorker).to receive(:perform_async)

        expect(subject['instance_metadata']).to include('domain' => bob.domain, 'software' => 'misskey')
        expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async)
      end
    end

    context 'with untrusted counts' do
      before do
        status.status_stat.tap do |status_stat|
          status_stat.untrusted_reblogs_count = 30
          status_stat.untrusted_favourites_count = 40
          status_stat.save
        end
      end

      it 'shows the untrusted counts' do
        expect(subject['reblogs_count']).to eq(30)
        expect(subject['favourites_count']).to eq(40)
      end
    end

    context 'with created_at' do
      it 'is serialized as RFC 3339 datetime' do
        expect(subject)
          .to include(
            'created_at' => match_api_datetime_format
          )
      end
    end

    context 'when edited_at is populated' do
      let(:status) { Fabricate.build :status, edited_at: 3.days.ago }

      it 'is serialized as RFC 3339 datetime' do
        expect(subject)
          .to include(
            'edited_at' => match_api_datetime_format
          )
      end
    end

    context 'with a tagged collection' do
      let(:collection) { Fabricate(:collection) }

      before do
        status.tagged_objects.create!(object: collection, ap_type: 'FeaturedCollection', uri: ActivityPub::TagManager.instance.uri_for(collection))
      end

      it 'contains the tagged collection' do
        expect(subject)
          .to include(
            'tagged_collections' => [a_hash_including(
              'id' => collection.id.to_s
            )]
          )
      end
    end
  end
end
