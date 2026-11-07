# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSwitchDevice do
  describe '#revoke!' do
    let(:account) { Fabricate(:account) }

    def device_bound_to(session_activation)
      described_class.create!(account:, token_digest: SecureRandom.hex, first_seen_at: Time.current, last_seen_at: Time.current, trusted_at: Time.current, session_activation:)
    end

    it 'ends the bound session of the device account' do
      session_activation = Fabricate(:session_activation, user: Fabricate(:user, account:))
      device = device_bound_to(session_activation)

      device.revoke!

      expect(SessionActivation.exists?(session_activation.id)).to be false
      expect(device.reload).to_not be_trusted
    end

    it 'keeps a session of another account that merely viewed the linked account' do
      session_activation = Fabricate(:session_activation)
      device = device_bound_to(session_activation)

      device.revoke!

      expect(SessionActivation.exists?(session_activation.id)).to be true
      expect(device.reload).to_not be_trusted
    end
  end
end
