# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationMute do
  describe 'validations' do
    it 'is valid with a target_account' do
      mute = Fabricate.build(:avatar_decoration_mute, target_domain: nil, account: Fabricate(:account), target_account: Fabricate(:account))
      expect(mute).to be_valid
    end

    it 'is valid with a target_domain' do
      mute = described_class.new(account: Fabricate(:account), target_domain: 'example.com', target_account: nil)
      expect(mute).to be_valid
    end

    it 'is invalid without both target_account and target_domain' do
      mute = described_class.new(account: Fabricate(:account), target_account: nil, target_domain: nil)
      expect(mute).to_not be_valid
      expect(mute.errors[:base]).to include('must set either target_account_id or target_domain')
    end

    it 'is invalid with both target_account and target_domain' do
      mute = described_class.new(account: Fabricate(:account), target_account: Fabricate(:account), target_domain: 'example.com')
      expect(mute).to_not be_valid
      expect(mute.errors[:base]).to include('cannot set both target_account_id and target_domain')
    end

    it 'prevents duplicate account mutes' do
      source = Fabricate(:account)
      target = Fabricate(:account)
      described_class.create!(account: source, target_account: target)
      dup = described_class.new(account: source, target_account: target)
      expect(dup).to_not be_valid
    end

    it 'prevents duplicate domain mutes' do
      source = Fabricate(:account)
      described_class.create!(account: source, target_domain: 'example.com')
      dup = described_class.new(account: source, target_domain: 'example.com')
      expect(dup).to_not be_valid
    end
  end

  describe 'scopes' do
    let(:source) { Fabricate(:account) }
    let(:target) { Fabricate(:account) }

    describe '.for_account' do
      it 'returns mutes for the given account' do
        mute = described_class.create!(account: source, target_account: target)
        expect(described_class.for_account(source.id)).to contain_exactly(mute)
      end
    end

    describe '.by_target_account' do
      it 'filters by target account' do
        mute = described_class.create!(account: source, target_account: target)
        expect(described_class.by_target_account(target.id)).to contain_exactly(mute)
      end
    end

    describe '.by_target_domain' do
      it 'filters by target domain' do
        mute = described_class.create!(account: source, target_domain: 'example.com')
        expect(described_class.by_target_domain('example.com')).to contain_exactly(mute)
      end
    end
  end
end
