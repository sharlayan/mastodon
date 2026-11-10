# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::REST::Account::RequestScopedCache do
  subject(:store) { RequestStore.store[described_class::STORE_KEY] }

  let(:account) { Fabricate(:account) }
  let(:viewer) { Fabricate(:user) }
  let(:other_viewer) { Fabricate(:user) }

  def serialize(record, user, serializer: REST::AccountSerializer, options: {})
    ActiveModelSerializers::SerializableResource.new(
      record,
      { serializer: serializer, scope: user, scope_name: :current_user }.merge(options)
    ).as_json
  end

  around do |example|
    RequestStore.begin!
    example.run
    RequestStore.clear!
    RequestStore.end!
  end

  context 'when serializing the same account twice in one request' do
    it 'reuses a cached copy without recomputing the bio and keeps the cache intact when the caller mutates it' do
      first = serialize(account, viewer)

      expect_any_instance_of(REST::AccountSerializer).to_not receive(:note) # rubocop:disable RSpec/AnyInstance
      second = serialize(account, viewer)

      expect(second).to eq(first)
      expect(second).to_not equal(first)
      expect(store.size).to eq 1

      second[:username] = 'mutated'

      expect(serialize(account, viewer)[:username]).to eq account.username
    end
  end

  context 'when the viewer or serializer differs' do
    it 'caches each viewer and serializer separately' do
      serialize(account, viewer)
      serialize(account, other_viewer)

      expect(store.size).to eq 2

      serialize(account, viewer, serializer: REST::PartialAccountSerializer)

      expect(store.size).to eq 3
    end
  end

  context 'when a fields option restricts the payload' do
    it 'skips the cache' do
      serialize(account, viewer, options: { fields: [:id] })

      expect(store).to be_nil
    end
  end

  context 'when the request store is inactive' do
    around do |example|
      RequestStore.end!
      example.run
      RequestStore.begin!
    end

    it 'serializes without caching' do
      expect(serialize(account, viewer)[:username]).to eq account.username
      expect(RequestStore.store[described_class::STORE_KEY]).to be_nil
    end
  end
end
