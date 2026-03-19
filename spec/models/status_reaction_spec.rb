# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusReaction do
  let(:account) { Fabricate(:account) }
  let(:status)  { Fabricate(:status) }

  describe 'validations' do
    it 'allows a valid unicode emoji' do
      reaction = described_class.new(account: account, status: status, name: '👍')
      expect(reaction).to be_valid
    end

    it 'requires a name' do
      reaction = described_class.new(account: account, status: status, name: '')
      expect(reaction).to_not be_valid
    end

    it 'enforces uniqueness of account, status, and name' do
      described_class.create!(account: account, status: status, name: '👍')
      duplicate = described_class.new(account: account, status: status, name: '👍')
      expect(duplicate).to_not be_valid
    end

    it 'allows different emoji names on the same status by the same account with higher limit' do
      stub_const('StatusReactionValidator::LIMIT', 2)
      described_class.create!(account: account, status: status, name: '👍')
      reaction = described_class.new(account: account, status: status, name: '❤️')
      expect(reaction).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to account' do
      reaction = described_class.new(account: account, status: status, name: '👍')
      expect(reaction.account).to eq account
    end

    it 'belongs to status' do
      reaction = described_class.new(account: account, status: status, name: '👍')
      expect(reaction.status).to eq status
    end
  end

  describe '#users' do
    it 'returns accounts that reacted with the same emoji' do
      reaction = described_class.create!(account: account, status: status, name: '👍')
      expect(reaction.users).to include(account)
    end
  end

  describe '#account_ids' do
    it 'returns string IDs of accounts that reacted' do
      reaction = described_class.create!(account: account, status: status, name: '👍')
      expect(reaction.account_ids).to include(account.id.to_s)
    end
  end

  describe 'cache counters' do
    it 'increments reactions_count on create' do
      expect { described_class.create!(account: account, status: status, name: '👍') }
        .to change { status.reload.reactions_count }.by(1)
    end

    it 'decrements reactions_count on destroy' do
      reaction = described_class.create!(account: account, status: status, name: '👍')
      expect { reaction.destroy! }
        .to change { status.reload.reactions_count }.by(-1)
    end
  end

  describe 'reblog handling' do
    let(:original) { Fabricate(:status) }
    let(:reblog)   { Fabricate(:status, reblog: original) }

    it 'reacts to the original status when given a reblog' do
      reaction = described_class.create!(account: account, status: reblog, name: '👍')
      expect(reaction.status).to eq original
    end
  end
end
