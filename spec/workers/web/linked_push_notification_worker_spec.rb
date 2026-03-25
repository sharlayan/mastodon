# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Web::LinkedPushNotificationWorker do
  subject { described_class.new }

  let(:endpoint)         { 'https://updates.push.services.mozilla.com/push/v1/subscription-id' }
  let(:main_user)        { Fabricate(:user) }
  let(:linked_account)   { Fabricate(:account) }
  let(:from_account)     { Fabricate(:account) }
  let(:status)           { Fabricate(:status, account: from_account) }
  let(:notification)     { Fabricate(:notification, account: linked_account, activity: status, type: :favourite) }
  let(:vapid_public_key) { 'BB37UCyc8LLX4PNQSe-04vSFvpUWGrENubUaslVFM_l5TxcGVMY0C3RXPeUJAQHKYlcOM2P4vTYmkoo0VZGZTM4=' }
  let(:vapid_private_key) { 'OPrw1Sum3gRoL4-DXfSCC266r-qfFSRZrnj8MgIhRHg=' }
  let(:contact_email) { 'sender@example.com' }
  let(:subscription) do
    Fabricate(:web_push_subscription,
              user: main_user,
              endpoint: endpoint,
              data: { alerts: { notification.type => true } })
  end

  around do |example|
    original_private = Rails.configuration.x.vapid.private_key
    original_public  = Rails.configuration.x.vapid.public_key
    Rails.configuration.x.vapid.private_key = vapid_private_key
    Rails.configuration.x.vapid.public_key  = vapid_public_key
    example.run
    Rails.configuration.x.vapid.private_key = original_private
    Rails.configuration.x.vapid.public_key  = original_public
  end

  before do
    Setting.site_contact_email = contact_email
    allow(JWT).to receive(:encode).and_return('jwt.encoded.payload')
    stub_request(:post, endpoint).to_return(status: 201, body: '')
    subscription
  end

  describe '#perform' do
    it 'sends a push notification to the main user subscriptions' do
      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to have_been_made.once
    end

    it 'does nothing when main user is not found' do
      subject.perform(0, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'does nothing when notification is not found' do
      subject.perform(main_user.id, 0)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'does nothing when notification is too old' do
      notification.update!(updated_at: 3.days.ago)

      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    context 'when endpoint returns 4xx (except 408/429)' do
      before do
        stub_request(:post, endpoint).to_return(status: 410, body: '')
      end

      it 'does not raise' do
        expect { subject.perform(main_user.id, notification.id) }.to_not raise_error
      end
    end
  end
end
