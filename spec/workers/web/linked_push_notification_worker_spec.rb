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
  let(:session_activation) { Fabricate(:session_activation, user: main_user).tap { |activation| activation.update!(access_token: subscription.access_token) } }
  let!(:device) do
    AccountSwitchDevice.create!(account: linked_account, token_digest: SecureRandom.hex, first_seen_at: Time.current, last_seen_at: Time.current, trusted_at: Time.current, session_activation: session_activation)
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

    it 'skips subscriptions whose session is not authorized for the linked account' do
      device.update!(revoked_at: Time.current)

      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'skips subscriptions of other sessions of the main user' do
      device.update!(session_activation: Fabricate(:session_activation, user: main_user))

      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'respects the alert settings of the subscription' do
      subscription.update!(data: { alerts: { notification.type => false } })

      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'does nothing when the main user is disabled' do
      main_user.update!(disabled: true)

      subject.perform(main_user.id, notification.id)

      expect(a_request(:post, endpoint)).to_not have_been_made
    end

    it 'does nothing when the main user or notification is not found, or the notification is too old' do
      subject.perform(0, notification.id)
      subject.perform(main_user.id, 0)
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
