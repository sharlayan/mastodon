# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/create endpoint' do
  let(:user)      { Fabricate(:user) }
  let(:account)   { user.account }
  let(:token)     { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/notes/create with specified visibility' do
    let(:recipient) { Fabricate(:account, username: 'bob') }

    it 'maps specified to a direct status and injects visibleUserIds as non-silent mentions' do
      post '/api/notes/create', params: { i: token, text: 'hi there', visibility: 'specified', visibleUserIds: [recipient.id.to_s] }, as: :json

      expect(response).to have_http_status(200)

      status = account.statuses.last
      expect(status.visibility).to eq('direct')
      expect(status.text).to start_with("@#{recipient.acct}")

      mention = status.mentions.find_by(account_id: recipient.id)
      expect(mention).to be_present
      expect(mention.silent).to be(false)
    end

    it 'does not duplicate a recipient already mentioned in the text' do
      post '/api/notes/create', params: { i: token, text: "@#{recipient.acct} hi", visibility: 'specified', visibleUserIds: [recipient.id.to_s] }, as: :json

      expect(response).to have_http_status(200)

      status = account.statuses.last
      expect(status.text.scan("@#{recipient.acct}").size).to eq(1)
      expect(status.mentions.where(account_id: recipient.id).count).to eq(1)
    end

    it 'leaves non-direct visibilities untouched' do
      post '/api/notes/create', params: { i: token, text: 'public post', visibility: 'public', visibleUserIds: [recipient.id.to_s] }, as: :json

      expect(response).to have_http_status(200)

      status = account.statuses.last
      expect(status.visibility).to eq('public')
      expect(status.text).to eq('public post')
    end
  end

  it 'queues timeline and federation distribution outside the controller transaction' do
    transaction_depth = ApplicationRecord.connection.open_transactions
    queued_at_depth = {}

    allow(DistributionWorker).to receive(:perform_async) do
      queued_at_depth[:timeline] = ApplicationRecord.connection.open_transactions
    end
    allow(ActivityPub::DistributionWorker).to receive(:perform_async) do
      queued_at_depth[:federation] = ApplicationRecord.connection.open_transactions
    end

    post '/api/notes/create', params: { i: token, text: 'distributed post', visibility: 'public' }, as: :json

    expect(response).to have_http_status(200)
    expect(queued_at_depth).to eq(timeline: transaction_depth, federation: transaction_depth)
  end
end
