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

  describe '.reaction_groups_map batch preloading' do
    def count_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
        count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] || /^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/.match?(payload[:sql])
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    let(:reactors) { Fabricate.times(3, :account) }

    before do
      reactors.each { |reactor| described_class.create!(account: reactor, status: status, name: '👍') }
    end

    it 'preloads users and account_ids so grouped records need no further queries' do
      record = Status.reaction_groups_map([status.id])[status.id].first

      expect(count_queries { record.account_ids }).to eq(0)
      expect(count_queries { record.users }).to eq(0)
      expect(record.account_ids).to match_array(reactors.map { |reactor| reactor.id.to_s })
      expect(record.users).to match_array(reactors)
    end

    it 'keeps the query count flat as the number of reaction groups grows' do
      one_group = count_queries { Status.reaction_groups_map([status.id]) }

      emojis = %w(😀 😁 😂 🤣)
      Fabricate.times(4, :account).each_with_index do |reactor, index|
        described_class.create!(account: reactor, status: status, name: emojis[index])
      end
      many_groups = count_queries { Status.reaction_groups_map([status.id]) }

      expect(many_groups).to eq(one_group)
    end

    it 'caps preloaded users at the display limit while keeping full account_ids' do
      extra = Fabricate.times(StatusReaction::USERS_DISPLAY_LIMIT, :account)
      extra.each { |reactor| described_class.create!(account: reactor, status: status, name: '👍') }

      record = Status.reaction_groups_map([status.id])[status.id].first

      expect(record.users.size).to eq(StatusReaction::USERS_DISPLAY_LIMIT)
      expect(record.account_ids.size).to eq(3 + StatusReaction::USERS_DISPLAY_LIMIT)
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
