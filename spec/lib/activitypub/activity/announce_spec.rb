# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Announce do
  subject { described_class.new(json, sender) }

  let(:sender)    { Fabricate(:account, followers_url: 'http://example.com/followers', uri: 'https://example.com/actor', domain: 'example.com') }
  let(:recipient) { Fabricate(:account) }
  let(:status)    { Fabricate(:status, account: recipient) }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Announce',
      actor: 'https://example.com/actor',
      object: object_json,
      to: 'http://example.com/followers',
    }.with_indifferent_access
  end

  let(:unknown_object_json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'https://example.com/actor/hello-world',
      type: 'Note',
      attributedTo: 'https://example.com/actor',
      content: 'Hello world',
      to: 'http://example.com/followers',
    }
  end

  describe '#perform' do
    context 'when sender is followed by a local account' do
      before do
        Fabricate(:account).follow!(sender)
        stub_request(:get, 'https://example.com/actor/hello-world').to_return(body: unknown_object_json.to_json, headers: { 'Content-Type': 'application/activity+json' })
        subject.perform
      end

      context 'with known status' do
        let(:object_json) do
          ActivityPub::TagManager.instance.uri_for(status)
        end

        it 'creates a reblog by sender of status' do
          expect(sender.reblogged?(status)).to be true
        end
      end

      context 'with unknown status' do
        let(:object_json) { 'https://example.com/actor/hello-world' }

        it 'creates a reblog by sender of status' do
          reblog = sender.statuses.first

          expect(reblog).to_not be_nil
          expect(reblog.reblog.text).to eq 'Hello world'
        end
      end

      context 'when self-boost of a previously unknown status with correct attributedTo' do
        let(:object_json) do
          {
            id: 'https://example.com/actor#bar',
            type: 'Note',
            content: 'Lorem ipsum',
            attributedTo: 'https://example.com/actor',
            to: 'http://example.com/followers',
          }
        end

        it 'creates a reblog by sender of status' do
          expect(sender.reblogged?(sender.statuses.first)).to be true
        end
      end

      context 'when self-boost of a previously unknown status with correct attributedTo, inlined Collection in audience' do
        let(:object_json) do
          {
            id: 'https://example.com/actor#bar',
            type: 'Note',
            content: 'Lorem ipsum',
            attributedTo: 'https://example.com/actor',
            to: {
              type: 'OrderedCollection',
              id: 'http://example.com/followers',
              first: 'http://example.com/followers?page=true',
            },
          }
        end

        it 'creates a reblog by sender of status' do
          expect(sender.reblogged?(sender.statuses.first)).to be true
        end
      end
    end

    context 'when the status belongs to a local user' do
      before do
        subject.perform
      end

      let(:object_json) do
        ActivityPub::TagManager.instance.uri_for(status)
      end

      it 'creates a reblog by sender of status' do
        expect(sender.reblogged?(status)).to be true
      end
    end

    context 'when the sender domain rejects relay but the boost did not arrive through a relay' do
      before do
        Fabricate(:domain_block, domain: sender.domain, reject_relay: true)
        subject.perform
      end

      let(:object_json) do
        ActivityPub::TagManager.instance.uri_for(status)
      end

      it 'creates a reblog by sender of status' do
        expect(sender.reblogged?(status)).to be true
      end
    end

    context 'when the sender is relayed' do
      subject { described_class.new(json, sender, relayed_through_actor: relay_account) }

      let!(:relay_account) { Fabricate(:account, inbox_url: 'https://relay.example.com/inbox', domain: 'relay.example.com') }
      let!(:relay) { Fabricate(:relay, inbox_url: 'https://relay.example.com/inbox') }

      let(:object_json) { 'https://example.com/actor/hello-world' }

      before do
        stub_request(:get, 'https://example.com/actor/hello-world').to_return(body: unknown_object_json.to_json, headers: { 'Content-Type': 'application/activity+json' })
      end

      context 'when the relay is enabled' do
        before do
          relay.update(state: :accepted)
          subject.perform
        end

        it 'fetches the remote status' do
          expect(a_request(:get, 'https://example.com/actor/hello-world')).to have_been_made
          expect(Status.find_by(uri: 'https://example.com/actor/hello-world').text).to eq 'Hello world'
        end
      end

      context 'when the relay suppresses the public timeline stream' do
        before do
          relay.update(state: :accepted, suppress_public_timeline_stream: true)
          subject.perform
        end

        it 'passes the suppression setting to the fetched status distribution' do
          status = Status.find_by(uri: 'https://example.com/actor/hello-world')

          expect(DistributionWorker)
            .to have_enqueued_sidekiq_job(status.id, hash_including('suppress_public_timeline_stream' => true))
        end
      end

      context 'when the relay is enabled but the sender domain rejects relay' do
        before do
          Fabricate(:domain_block, domain: sender.domain, reject_relay: true)
          relay.update(state: :accepted)
          subject.perform
        end

        it 'does not fetch the remote status' do
          expect(a_request(:get, 'https://example.com/actor/hello-world')).to_not have_been_made
          expect(Status.find_by(uri: 'https://example.com/actor/hello-world')).to be_nil
        end

        it 'does not create anything' do
          expect(sender.statuses.count).to eq 0
        end
      end

      context 'when the relay is disabled' do
        before do
          subject.perform
        end

        it 'does not fetch the remote status' do
          expect(a_request(:get, 'https://example.com/actor/hello-world')).to_not have_been_made
          expect(Status.find_by(uri: 'https://example.com/actor/hello-world')).to be_nil
        end

        it 'does not create anything' do
          expect(sender.statuses.count).to eq 0
        end
      end
    end

    context 'when a relay announces a post from a domain that rejects relay delivery' do
      subject { described_class.new(json, relay_account) }

      let!(:relay_account) { Fabricate(:account, inbox_url: 'https://relay.example.com/inbox', domain: 'relay.example.com') }
      let(:relay) { Fabricate(:relay, inbox_url: 'https://relay.example.com/inbox', state: :accepted) }

      let(:json) do
        super().merge(actor: relay_account.uri)
      end

      let(:object_json) do
        {
          id: 'https://remote.example/users/alice/statuses/1',
          type: 'Note',
          attributedTo: 'https://remote.example/users/alice',
          content: 'Hello from a relay',
          to: 'https://www.w3.org/ns/activitystreams#Public',
        }
      end

      before do
        relay
        Fabricate(:domain_block, domain: 'remote.example', severity: :noop, reject_relay: true)
        subject.perform
      end

      it 'rejects the post based on its original author domain' do
        expect(relay_account.statuses).to be_empty
        expect(Status.find_by(uri: 'https://remote.example/users/alice/statuses/1')).to be_nil
      end
    end

    context 'when a relay actor announces a post' do
      subject { described_class.new(json, relay_account) }

      let!(:relay_account) { Fabricate(:account, inbox_url: 'https://relay.example.com/inbox', domain: 'relay.example.com') }
      let!(:relay) { Fabricate(:relay, inbox_url: relay_account.inbox_url, state: :accepted, suppress_public_timeline_stream: true) }
      let!(:remote_account) { Fabricate(:account, uri: 'https://remote.example/users/alice', domain: 'remote.example') }

      let(:json) do
        super().merge(actor: relay_account.uri)
      end

      let(:object_json) { 'https://remote.example/users/alice/statuses/1' }

      let(:fetched_object_json) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: object_json,
          type: 'Note',
          attributedTo: 'https://remote.example/users/alice',
          content: 'Hello from a relay',
          to: 'https://www.w3.org/ns/activitystreams#Public',
        }
      end

      before do
        relay
        remote_account
        stub_request(:get, object_json).to_return(body: fetched_object_json.to_json, headers: { 'Content-Type': 'application/activity+json' })
        subject.perform
      end

      it 'passes the suppression setting to the fetched status distribution' do
        status = Status.find_by(uri: object_json)

        expect(DistributionWorker)
          .to have_enqueued_sidekiq_job(status.id, hash_including('suppress_public_timeline_stream' => true))
      end
    end

    context 'when the sender has no relevance to local activity' do
      before do
        subject.perform
      end

      let(:object_json) do
        {
          id: 'https://example.com/actor#bar',
          type: 'Note',
          content: 'Lorem ipsum',
          to: 'http://example.com/followers',
          attributedTo: 'https://example.com/actor',
        }
      end

      it 'does not create anything' do
        expect(sender.statuses.count).to eq 0
      end
    end
  end
end
