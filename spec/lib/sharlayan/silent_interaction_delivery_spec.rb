# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::SilentInteractionDelivery do
  describe '.suppressed_for?' do
    it 'suppresses bird.makeup and BirdsiteLive servers for quotes and replies but allows ordinary remote servers and local accounts' do
      bird_makeup = Fabricate(:account, domain: 'bird.makeup')
      bridge = Fabricate(:account, domain: 'bridge.example')
      remote_account = Fabricate(:account, domain: 'social.example')
      Fabricate(:instance_metadata, domain: bridge.domain, software: 'BirdsiteLive')
      Fabricate(:instance_metadata, domain: remote_account.domain, software: 'mastodon')
      status = Fabricate(:status, account: bird_makeup)

      expect(described_class.suppressed_for?(bird_makeup)).to be(true)
      expect(described_class.suppressed_for?(bridge)).to be(true)
      expect(described_class.suppressed_for?(remote_account)).to be(false)
      expect(described_class.suppressed_for?(Fabricate(:account))).to be(false)
      expect(described_class.quote_policy_ignored_for?(status)).to be(true)
      expect(described_class.reply_suppressed_for?(status)).to be(true)
    end
  end
end
