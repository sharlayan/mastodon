# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat user timeline position restoration' do
  let(:viewer) { Fabricate(:user) }
  let(:target) { Fabricate(:account) }
  let(:token)  { Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'applies the date window Aria uses for time-machine and past-timeline pagination' do
    window_start = 100.days.ago.change(usec: 0)
    window_end = window_start + 1.day
    before_window = Fabricate(:status, account: target, id: Mastodon::Snowflake.id_at(window_start - 1.second), created_at: window_start - 1.second)
    in_window = Fabricate(:status, account: target, id: Mastodon::Snowflake.id_at(window_start + 1.hour), created_at: window_start + 1.hour)
    after_window = Fabricate(:status, account: target, id: Mastodon::Snowflake.id_at(window_end + 1.second), created_at: window_end + 1.second)

    post '/api/users/notes', params: {
      i: token,
      userId: MisskeyCompat::MiId.encode(target.id),
      sinceDate: window_start.to_i * 1000,
      untilDate: window_end.to_i * 1000,
      limit: 30,
    }, as: :json

    expect(response).to have_http_status(200)
    ids = response.parsed_body.pluck('id').map { |id| MisskeyCompat::MiId.decode(id).to_i }
    expect(ids).to contain_exactly(in_window.id)
    expect(ids).to not_include(before_window.id, after_window.id)
  end
end
