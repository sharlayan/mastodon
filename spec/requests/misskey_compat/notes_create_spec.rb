# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/create endpoint' do
  let(:user)      { Fabricate(:user) }
  let(:account)   { user.account }
  let(:token)     { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'MFM composition' do
    around do |example|
      mfm_enabled = Setting.mfm_enabled
      mfm_allow_composition = Setting.mfm_allow_composition
      example.run
    ensure
      Setting.mfm_enabled = mfm_enabled
      Setting.mfm_allow_composition = mfm_allow_composition
    end

    it 'uses the Markdown fallback when composition is disabled' do
      Setting.mfm_enabled = true
      Setting.mfm_allow_composition = false

      post '/api/notes/create', params: { i: token, text: '$[x2 fallback]' }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last).to have_attributes(content_type: 'text/markdown', mfm: false, mfm_text: nil, text: 'fallback')
    end

    it 'posts MFM when composition is enabled' do
      Setting.mfm_enabled = true
      Setting.mfm_allow_composition = true

      post '/api/notes/create', params: { i: token, text: '$[x2 enabled]' }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last).to have_attributes(content_type: 'text/x-mfm', mfm: true, mfm_text: '$[x2 enabled]')
    end
  end

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
      expect(response.parsed_body.dig(:createdNote, :visibleUserIds)).to contain_exactly(MisskeyCompat::MiId.encode(recipient.id))
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

  describe 'reaction errors' do
    let(:note) { Fabricate(:status) }

    it 'rejects duplicate creation and deletion without an existing reaction' do
      post '/api/notes/reactions/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id), reaction: '👍' }, as: :json
      expect(response).to have_http_status(204)

      post '/api/notes/reactions/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id), reaction: '👍' }, as: :json
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('ALREADY_REACTED')

      post '/api/notes/reactions/delete', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id) }, as: :json
      expect(response).to have_http_status(204)

      post '/api/notes/reactions/delete', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id) }, as: :json
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('NOT_REACTED')
    end
  end

  describe 'poll expiration' do
    it 'uses the Misskey absolute expiresAt value' do
      expires_at = 2.hours.from_now.change(usec: 0)

      post '/api/notes/create', params: { i: token, text: 'poll', poll: { choices: %w(One Two), multiple: false, expiresAt: expires_at.to_i * 1000 } }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.poll.expires_at).to be_within(1.second).of(expires_at)
    end
  end

  describe 'POST /api/notes/create with renoteId' do
    let(:quoted) { Fabricate(:status, account: Fabricate(:account, username: 'quoted')) }
    let(:renote_id) { MisskeyCompat::MiId.encode(quoted.id) }

    it 'keeps a content warning in a quote with no text' do
      post '/api/notes/create', params: { i: token, renoteId: renote_id, cw: 'Spoiler' }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last).to have_attributes(reblog_of_id: nil, spoiler_text: 'Spoiler')
      expect(account.statuses.last.quote.quoted_status).to eq(quoted)
    end

    it 'keeps an attached file in a quote with no text' do
      media = Fabricate(:media_attachment, account: account)

      post '/api/notes/create', params: { i: token, renoteId: renote_id, fileIds: [MisskeyCompat::MiId.encode(media.id)] }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.quote.quoted_status).to eq(quoted)
      expect(media.reload.status).to eq(account.statuses.last)
    end

    it 'keeps a poll in a quote with no text' do
      post '/api/notes/create', params: { i: token, renoteId: renote_id, poll: { choices: %w(One Two), multiple: false, expiredAfter: 3_600_000 } }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.quote.quoted_status).to eq(quoted)
      expect(account.statuses.last.poll.options).to eq(%w(One Two))
    end

    it 'rejects an indefinite poll instead of dropping it from a renote' do
      post '/api/notes/create', params: { i: token, renoteId: renote_id, poll: { choices: %w(One Two) } }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
      expect(account.statuses).to be_empty
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

    it 'limits a public reply to a home note to home visibility' do
      parent.update!(visibility: :unlisted)

      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(parent.id), visibility: 'public' }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.visibility).to eq('unlisted')
      expect(response.parsed_body.dig(:createdNote, :visibility)).to eq('home')
    end

    it 'limits a home reply to a followers note to followers visibility' do
      private_parent = Fabricate(:status, account: account, visibility: :private)

      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(private_parent.id), visibility: 'home' }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.visibility).to eq('private')
      expect(response.parsed_body.dig(:createdNote, :visibility)).to eq('followers')
    end

    it 'rejects a broader visibility when replying to a specified note' do
      specified_parent = Fabricate(:status, account: account, visibility: :direct)

      post '/api/notes/create', params: { i: token, text: 'a reply', replyId: MisskeyCompat::MiId.encode(specified_parent.id), visibility: 'public' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('CANNOT_REPLY_TO_SPECIFIED_VISIBILITY_NOTE_WITH_EXTENDED_VISIBILITY')
      expect(account.statuses.count).to eq(1)
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
