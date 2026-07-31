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

  describe 'POST /api/notes/create with replyId' do
    let(:parent) { Fabricate(:status, account: Fabricate(:account, username: 'bob')) }

    it 'threads the new note under the reply target' do
      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(parent.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:createdNote, :replyId)).to eq(MisskeyCompat::MiId.encode(parent.id))

      status = account.statuses.last
      expect(status.in_reply_to_id).to eq(parent.id)
      expect(status.in_reply_to_account_id).to eq(parent.account_id)
    end

    it 'keeps the note threaded when the client also prefixes a mention, as Flare does' do
      post '/api/notes/create', params: { i: token, text: "@#{parent.account.acct} a reply", replyId: MisskeyCompat::MiId.encode(parent.id) }, as: :json

      expect(response).to have_http_status(200)

      status = account.statuses.last
      expect(status.in_reply_to_id).to eq(parent.id)
      expect(status.mentions.where(account_id: parent.account_id).count).to eq(1)

      post '/api/notes/children', params: { i: token, noteId: MisskeyCompat::MiId.encode(parent.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(status.id))

      post '/api/notes/show', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:reply, :id)).to eq(MisskeyCompat::MiId.encode(parent.id))
    end

    it 'returns NO_SUCH_REPLY_TARGET for an unknown target' do
      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(Status.last&.id.to_i + 1_000_000) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_REPLY_TARGET')
    end

    it 'returns NO_SUCH_REPLY_TARGET for a target the user cannot see' do
      hidden = Fabricate(:status, account: Fabricate(:account, username: 'carol'), visibility: :direct)

      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(hidden.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_REPLY_TARGET')
    end
  end

  describe 'reactionAcceptance' do
    it 'stores and serializes the selected value' do
      post '/api/notes/create', params: { i: token, text: 'restricted reactions', reactionAcceptance: 'nonSensitiveOnly' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:createdNote, :reactionAcceptance)).to eq('nonSensitiveOnly')
      expect(account.statuses.last.reaction_acceptance).to eq('nonSensitiveOnly')
    end

    it 'applies the stored restriction to Misskey reaction requests' do
      post '/api/notes/create', params: { i: token, text: 'likes only', reactionAcceptance: 'likeOnly' }, as: :json
      note_id = response.parsed_body.dig(:createdNote, :id)
      reactor = Fabricate(:user)
      reactor_token = Fabricate(:accessible_access_token, resource_owner_id: reactor.id, scopes: 'write').token

      post '/api/notes/reactions/create', params: { i: reactor_token, noteId: note_id, reaction: '👍' }, as: :json

      expect(response).to have_http_status(204)
      expect(account.statuses.last.status_reactions.last).to have_attributes(account_id: reactor.account.id, name: "\u2764")
    end

    it 'updates and clears the value when explicitly requested' do
      status = Fabricate(:status, account: account, reaction_acceptance: 'likeOnly')

      post '/api/notes/update', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id), text: status.text, reactionAcceptance: 'likeOnlyForRemote' }, as: :json
      expect(response).to have_http_status(204)
      expect(status.reload.reaction_acceptance).to eq('likeOnlyForRemote')

      post '/api/notes/update', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id), text: status.text, reactionAcceptance: nil }, as: :json
      expect(response).to have_http_status(204)
      expect(status.reload.reaction_acceptance).to be_nil
    end

    it 'rejects an unsupported value' do
      post '/api/notes/create', params: { i: token, text: 'invalid', reactionAcceptance: 'customOnly' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
      expect(account.statuses).to be_empty
    end

    it 'preserves the value in scheduled note data' do
      post '/api/notes/create', params: { i: token, text: 'scheduled', reactionAcceptance: 'likeOnly', scheduledAt: 10.minutes.from_now.to_i * 1000 }, as: :json
      expect(response).to have_http_status(200)

      read_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token
      post '/api/notes/scheduled/list', params: { i: read_token }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.first.dig(:data, :reactionAcceptance)).to eq('likeOnly')
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
