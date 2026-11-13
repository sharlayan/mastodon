# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat bubble game endpoints' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }
  let(:now) { Time.utc(2026, 11, 12, 12, 0, 0) }
  let(:valid_params) { { score: 1200, seed: ((now - 1.hour).to_i * 1000).to_s, logs: [[0, 1.5, 2]], gameMode: 'normal', gameVersion: 3 } }

  before do
    Setting.misskey_compat_enabled = true
    travel_to(now)
  end

  after { Setting.misskey_compat_enabled = false }

  it 'validates scores per Misskey and rejects future, stale and non-numeric seeds' do
    post '/api/bubble-game/register', params: valid_params, as: :json
    expect(response).to have_http_status(401)

    [{ score: -1 }, { score: 1.5 }, { seed: '' }, { logs: [[1, 'x']] }, { gameMode: 1 }, { gameVersion: '3' }].each do |invalid|
      post '/api/bubble-game/register', params: valid_params.merge(invalid).merge(i: token), as: :json
      expect(response).to have_http_status(400), invalid.inspect
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    ['abc', ((now + 1.minute).to_i * 1000).to_s, ((now - 6.hours).to_i * 1000).to_s].each do |seed|
      redis.del(redis.keys('rate_limit:*:misskey_compat_bubble_game_interval:*'))
      post '/api/bubble-game/register', params: valid_params.merge(seed: seed, i: token), as: :json
      expect(response.parsed_body[:error]).to include(code: 'INVALID_SEED', id: 'eb627bc7-574b-4a52-a860-3c3eae772b88')
    end
    expect(MisskeyBubbleGameRecord.count).to eq(0)
  end

  it 'records a score, enforces the minimum interval and ranks the last week by score for the requested mode' do
    post '/api/bubble-game/register', params: valid_params.merge(i: token), as: :json
    expect(response).to have_http_status(204)
    record = MisskeyBubbleGameRecord.last
    expect(record).to have_attributes(account_id: user.account_id, score: 1200, seeded_at: now - 1.hour, logs: [[0, 1.5, 2]], game_mode: 'normal', game_version: 3, is_verified: false)

    post '/api/bubble-game/register', params: valid_params.merge(i: token, score: 5), as: :json
    expect(response).to have_http_status(429)

    other = Fabricate(:account)
    higher = MisskeyBubbleGameRecord.create!(account: other, seed: '1', seeded_at: now - 2.days, score: 9000, game_mode: 'normal', game_version: 3)
    MisskeyBubbleGameRecord.create!(account: other, seed: '1', seeded_at: now - 8.days, score: 99_999, game_mode: 'normal', game_version: 3)
    MisskeyBubbleGameRecord.create!(account: other, seed: '1', seeded_at: now - 1.day, score: 99_999, game_mode: 'square', game_version: 3)

    get '/api/bubble-game/ranking', params: { gameMode: 'normal' }

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to match([
                                            include(id: MisskeyCompat::MiId.encode(higher.id), score: 9000, user: include(id: MisskeyCompat::MiId.encode(other.id))),
                                            include(id: MisskeyCompat::MiId.encode(record.id), score: 1200, user: include(username: user.account.username)),
                                          ])

    post '/api/bubble-game/ranking', as: :json
    expect(response).to have_http_status(400)
  end
end
