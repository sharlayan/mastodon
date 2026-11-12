# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat reversi' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:token)       { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:read_token)  { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }
  let(:other_user)  { Fabricate(:user) }
  let(:other)       { other_user.account }
  let(:other_token) { MisskeyCompat::MiAuth.issue_native_token(other_user).token }

  before { Setting.misskey_compat_enabled = true }

  after { Setting.misskey_compat_enabled = false }

  def api(endpoint, params = {})
    post "/api/reversi/#{endpoint}", params: params, as: :json
    response.parsed_body
  end

  def create_game(**attributes)
    MisskeyReversiGame.create!({ account1: account, account2: other, map: MisskeyCompat::ReversiEngine::DEFAULT_MAP }.merge(attributes))
  end

  def mid(id)
    MisskeyCompat::MiId.encode(id)
  end

  describe 'matching' do
    it 'invites a specific user, lists the invitation and creates the game when the invitee accepts' do
      expect(api('match', i: token, userId: mid(other.id))).to be_blank
      expect(response).to have_http_status(204)

      invitations = api('invitations', i: other_token)
      expect(invitations.pluck(:id)).to eq([mid(account.id)])
      expect(invitations.first).to include(:username, :avatarUrl)

      game = api('match', i: other_token, userId: mid(account.id))
      expect(response).to have_http_status(200)
      expect(game).to include(user1Id: mid(account.id), user2Id: mid(other.id), isStarted: false, isEnded: false, bw: 'random', map: MisskeyCompat::ReversiEngine::DEFAULT_MAP, logs: [], timeLimitForEachTurn: 90, form1: nil, user1Ready: false)
      expect(game[:user1]).to include(id: mid(account.id))
      expect(api('invitations', i: other_token)).to eq([])

      expect(api('match', i: token, userId: mid(other.id))).to include(id: game[:id])
    end

    it 'matches anyone waiting, honors noIrregularRules and cancels pending requests' do
      api('match', i: token, noIrregularRules: true)
      expect(response).to have_http_status(204)

      api('cancel-match', i: token, userId: nil)
      expect(response).to have_http_status(204)
      expect(redis.zcard(MisskeyCompat::ReversiService::MATCH_ANY_KEY)).to eq(0)

      api('match', i: token, noIrregularRules: true)
      game = api('match', i: other_token)
      expect(game).to include(user1Id: mid(account.id), user2Id: mid(other.id), noIrregularRules: true)
      expect(redis.zcard(MisskeyCompat::ReversiService::MATCH_ANY_KEY)).to eq(0)

      api('match', i: token, userId: mid(other.id), multiple: true)
      api('cancel-match', i: token, userId: mid(other.id))
      expect(api('invitations', i: other_token)).to eq([])
    end

    it 'rejects self matches, unknown users, invalid params and insufficient permissions' do
      api('match', i: token, userId: mid(account.id))
      expect(response.parsed_body[:error]).to include(code: 'TARGET_IS_YOURSELF', id: '96fd7bd6-d2bc-426c-a865-d055dcd2828e')

      api('match', i: token, userId: mid(Fabricate(:account, suspended: true).id))
      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER', id: '0b4f0559-b484-4e31-9581-3f73cee89b28')

      api('match', i: token, multiple: 'yes')
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM')

      api('match', i: read_token)
      expect(response).to have_http_status(403)

      api('invitations')
      expect(response).to have_http_status(401)
    end

    it 'does not deliver invitations across blocks' do
      other.block!(account)

      api('match', i: token, userId: mid(other.id))
      expect(response).to have_http_status(204)
      expect(api('invitations', i: other_token)).to eq([])
    end

    it 'cleans unstarted games older than ten minutes' do
      stale = create_game(created_at: 11.minutes.ago)
      started = create_game(created_at: 11.minutes.ago, started_at: 11.minutes.ago)

      api('match', i: token)

      expect(MisskeyReversiGame.exists?(stale.id)).to be(false)
      expect(MisskeyReversiGame.exists?(started.id)).to be(true)
    end
  end

  describe 'games' do
    it 'lists started games publicly, the caller games with my, and paginates' do
      pending_game = create_game
      older = create_game(started_at: 2.minutes.ago)
      newer = create_game(started_at: 1.minute.ago, ended_at: Time.current, winner_account_id: other.id)
      unrelated = MisskeyReversiGame.create!(account1: Fabricate(:account), account2: Fabricate(:account), map: %w(--), started_at: Time.current)

      body = api('games')
      expect(body.pluck(:id)).to eq([mid(unrelated.id), mid(newer.id), mid(older.id)])
      expect(body.second).to include(isEnded: true, winnerId: mid(other.id), winner: include(id: mid(other.id)))
      expect(body.first).to_not include(:logs, :map, :user1Ready)

      expect(api('games', i: read_token, my: true).pluck(:id)).to eq([mid(newer.id), mid(older.id), mid(pending_game.id)])
      expect(api('games', untilId: mid(newer.id), limit: 1).pluck(:id)).to eq([mid(older.id)])
      expect(api('games', sinceId: mid(older.id)).pluck(:id)).to eq([mid(newer.id), mid(unrelated.id)])
    end
  end

  describe 'show-game, verify and surrender' do
    it 'shows a game, reports desync by crc32 and returns not-found ids' do
      game = create_game(started_at: Time.current, black: 1, crc32: '1090129541')

      expect(api('show-game', gameId: mid(game.id))).to include(id: mid(game.id), black: 1, user1Ready: false)

      expect(api('verify', gameId: mid(game.id), crc32: '1090129541')).to eq({ 'desynced' => false })
      expect(api('verify', gameId: mid(game.id), crc32: '1')).to include(desynced: true, game: include(id: mid(game.id)))

      api('verify', gameId: mid(game.id))
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM')

      { 'show-game' => 'f13a03db-fae1-46c9-87f3-43c8165419e1', 'verify' => '8fb05624-b525-43dd-90f7-511852bdfeee', 'surrender' => 'ace0b11f-e0a6-4076-a30d-e8284c81b2df' }.each do |endpoint, id|
        api(endpoint, i: token, gameId: '0000000000000000', crc32: '0')
        expect(response).to have_http_status(404)
        expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_GAME', id: id)
      end
    end

    it 'lets a participant surrender once and rejects others' do
      game = create_game(started_at: Time.current, black: 1)

      api('surrender', i: MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user)).token, gameId: mid(game.id))
      expect(response).to have_http_status(403)
      expect(response.parsed_body[:error]).to include(code: 'ACCESS_DENIED', id: '6e04164b-a992-4c93-8489-2123069973e1')

      api('surrender', i: token, gameId: mid(game.id))
      expect(response).to have_http_status(204)
      expect(game.reload).to have_attributes(ended?: true, winner_account_id: other.id, surrendered_account_id: account.id, timeout_account_id: nil)

      api('surrender', i: other_token, gameId: mid(game.id))
      expect(response.parsed_body[:error]).to include(code: 'ALREADY_ENDED', id: '6c2ad4a6-cbf1-4a5b-b187-b772826cfc6d')
    end
  end
end
