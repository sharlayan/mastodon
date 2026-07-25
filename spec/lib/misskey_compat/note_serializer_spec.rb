# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::NoteSerializer do
  describe 'local mentions' do
    it 'adds the configured local port to an already-qualified mention' do
      mentioned_account = Fabricate(:account, username: 'bob')
      status = Fabricate(:status, text: '@bob@localhost hello')
      Fabricate(:mention, status: status, account: mentioned_account)
      allow(Rails.configuration.x).to receive(:local_domain).and_return('localhost:3000')

      serialized = described_class.serialize(status)

      expect(serialized[:text]).to eq('@bob@localhost:3000 hello')
    end

    it 'does not duplicate the port when the mention already includes it' do
      mentioned_account = Fabricate(:account, username: 'bob')
      status = Fabricate(:status, text: '@bob@localhost:3000 hello')
      Fabricate(:mention, status: status, account: mentioned_account)
      allow(Rails.configuration.x).to receive(:local_domain).and_return('localhost:3000')

      serialized = described_class.serialize(status)

      expect(serialized[:text]).to eq('@bob@localhost:3000 hello')
    end
  end
end
