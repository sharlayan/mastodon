# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::SilentInteractionDelivery do
  describe '.suppressed_for?' do
    it 'suppresses the official bird.makeup domain without cached metadata' do
      account = Fabricate(:account, domain: 'bird.makeup')

      expect(described_class.suppressed_for?(account)).to be(true)
    end

    it 'suppresses servers identified as BirdsiteLive' do
      account = Fabricate(:account, domain: 'bridge.example')
      Fabricate(:instance_metadata, domain: account.domain, software: 'BirdsiteLive')

      expect(described_class.suppressed_for?(account)).to be(true)
    end

    it 'allows ordinary remote servers and local accounts' do
      remote_account = Fabricate(:account, domain: 'social.example')
      Fabricate(:instance_metadata, domain: remote_account.domain, software: 'mastodon')

      expect(described_class.suppressed_for?(remote_account)).to be(false)
      expect(described_class.suppressed_for?(Fabricate(:account))).to be(false)
    end

    it 'uses the same target classification for quotes and replies' do
      status = Fabricate(:status, account: Fabricate(:account, domain: 'bird.makeup'))

      expect(described_class.quote_policy_ignored_for?(status)).to be(true)
      expect(described_class.reply_suppressed_for?(status)).to be(true)
    end
  end
end
