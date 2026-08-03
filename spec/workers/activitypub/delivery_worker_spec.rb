# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::DeliveryWorker do
  include RoutingHelper

  let(:sender) { Fabricate(:account) }
  let(:payload) { 'test' }
  let(:url) { 'https://example.com/api' }

  before do
    allow(sender).to receive(:remote_followers_hash).with(url).and_return('somehash')
    allow(Account).to receive(:find).with(sender.id).and_return(sender)
  end

  describe 'perform' do
    context 'with successful request' do
      before { stub_request(:post, url).to_return(status: 200) }

      it 'performs a request to synchronize collection' do
        subject.perform(payload, sender.id, url, { synchronize_followers: true })

        expect(request_to_url)
          .to have_been_made.once
      end

      context 'when using a numeric ID based scheme' do
        let(:sender) { Fabricate(:account, id_scheme: :numeric_ap_id) }

        it 'performs a request to synchronize collection' do
          subject.perform(payload, sender.id, url, { synchronize_followers: true })

          expect(request_to_url)
            .to have_been_made.once
        end
      end

      it 'counts the delivery against the target domain' do
        subject.perform(payload, sender.id, url)

        expect(Sharlayan::FederationRequestTracker.flush!).to eq(1)
        expect(FederationRequestStatistic.find_by(domain: 'example.com'))
          .to have_attributes(deliver_succeeded_count: 1, deliver_failed_count: 0)
      end

      def request_to_url
        a_request(:post, url)
          .with(
            headers: {
              'Collection-Synchronization' => <<~VALUES.squish,
                collectionId="#{ActivityPub::TagManager.instance.followers_uri_for(sender)}", digest="somehash", url="#{account_followers_synchronization_url(sender)}"
              VALUES
            }
          )
      end
    end

    context 'with failing request' do
      before { stub_request(:post, url).to_return(status: 500) }

      it 'raises error' do
        expect { subject.perform(payload, sender.id, url) }
          .to raise_error Mastodon::UnexpectedResponseError
      end

      it 'counts the failure against the target domain' do
        expect { subject.perform(payload, sender.id, url) }
          .to raise_error Mastodon::UnexpectedResponseError

        expect(Sharlayan::FederationRequestTracker.flush!).to eq(1)
        expect(FederationRequestStatistic.find_by(domain: 'example.com'))
          .to have_attributes(deliver_succeeded_count: 0, deliver_failed_count: 1)
      end
    end
  end
end
