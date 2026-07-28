# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyRegistryItem do
  let(:account) { Fabricate(:account) }

  def build_item(value:, scope: %w(client base))
    described_class.new(account: account, domain: nil, scope: scope, key: SecureRandom.hex(8), value: value)
  end

  it 'rejects values above the per-item byte limit' do
    item = build_item(value: 'x' * described_class::MAX_VALUE_BYTES)

    expect(item).to_not be_valid
    expect(item.errors).to include(:value)
  end

  it 'rejects writes when a scope already exceeds its byte quota' do
    existing = build_item(value: 'small')
    existing.save!
    existing.update_column(:value, 'x' * described_class::MAX_SCOPE_BYTES)
    item = build_item(value: 'more')

    expect(item).to_not be_valid
    expect(item.errors[:value]).to include('registry scope storage limit exceeded')
  end

  it 'rejects writes when a scope reaches its item limit' do
    now = Time.current
    described_class.insert_all!(
      Array.new(described_class::MAX_SCOPE_ITEMS) do |index|
        {
          account_id: account.id,
          domain: nil,
          scope: %w(client base),
          key: "key-#{index}",
          value: true,
          created_at: now,
          updated_at: now,
        }
      end
    )
    item = build_item(value: true)

    expect(item).to_not be_valid
    expect(item.errors[:base]).to include('registry scope item limit exceeded')
  end

  it 'rejects writes when the account already exceeds its byte quota' do
    existing = build_item(value: 'small', scope: %w(other))
    existing.save!
    existing.update_column(:value, 'x' * described_class::MAX_ACCOUNT_BYTES)
    item = build_item(value: 'more')

    expect(item).to_not be_valid
    expect(item.errors[:value]).to include('registry account storage limit exceeded')
  end
end
