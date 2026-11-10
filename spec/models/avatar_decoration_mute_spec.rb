# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationMute do
  describe 'validations' do
    it 'requires exactly one of target_account and target_domain' do
      account_mute = Fabricate.build(:avatar_decoration_mute, target_domain: nil, account: Fabricate(:account), target_account: Fabricate(:account))
      domain_mute = described_class.new(account: Fabricate(:account), target_domain: 'example.com', target_account: nil)
      neither = described_class.new(account: Fabricate(:account), target_account: nil, target_domain: nil)
      both = described_class.new(account: Fabricate(:account), target_account: Fabricate(:account), target_domain: 'example.com')

      expect(account_mute).to be_valid
      expect(domain_mute).to be_valid
      expect(neither).to_not be_valid
      expect(neither.errors[:base]).to include('must set either target_account_id or target_domain')
      expect(both).to_not be_valid
      expect(both.errors[:base]).to include('cannot set both target_account_id and target_domain')
    end

    it 'prevents duplicate account and domain mutes' do
      source = Fabricate(:account)
      target = Fabricate(:account)
      described_class.create!(account: source, target_account: target)
      described_class.create!(account: source, target_domain: 'example.com')

      expect(described_class.new(account: source, target_account: target)).to_not be_valid
      expect(described_class.new(account: source, target_domain: 'example.com')).to_not be_valid
    end
  end

  describe 'scopes' do
    it 'filter mutes by account, target account and target domain' do
      source = Fabricate(:account)
      target = Fabricate(:account)
      account_mute = described_class.create!(account: source, target_account: target)
      domain_mute = described_class.create!(account: source, target_domain: 'example.com')

      expect(described_class.for_account(source.id)).to contain_exactly(account_mute, domain_mute)
      expect(described_class.by_target_account(target.id)).to contain_exactly(account_mute)
      expect(described_class.by_target_domain('example.com')).to contain_exactly(domain_mute)
    end
  end
end
