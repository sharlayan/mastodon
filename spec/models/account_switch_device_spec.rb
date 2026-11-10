# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSwitchDevice do
  describe '#revoke!' do
    let(:account) { Fabricate(:account) }

    def device_bound_to(session_activation)
      described_class.create!(account:, token_digest: SecureRandom.hex, first_seen_at: Time.current, last_seen_at: Time.current, trusted_at: Time.current, session_activation:)
    end

    it 'ends the bound session of the device account but keeps a session of another account that merely viewed it' do
      own_session = Fabricate(:session_activation, user: Fabricate(:user, account:))
      viewer_session = Fabricate(:session_activation)
      own_device = device_bound_to(own_session)
      viewer_device = device_bound_to(viewer_session)

      own_device.revoke!
      viewer_device.revoke!

      expect(SessionActivation.exists?(own_session.id)).to be false
      expect(own_device.reload).to_not be_trusted
      expect(SessionActivation.exists?(viewer_session.id)).to be true
      expect(viewer_device.reload).to_not be_trusted
    end
  end
end
