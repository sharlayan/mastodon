# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat timeline position restoration' do
  let(:user)  { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns up to 100 notes from the requested date window' do
    window_start = 2.hours.ago.change(usec: 0)
    window_end = window_start + 2.minutes
    before_window = Fabricate(:status, account: user.account, id: Mastodon::Snowflake.id_at(window_start - 1.second), text: 'before')
    in_window = Array.new(45) do |index|
      Fabricate(:status, account: user.account, id: Mastodon::Snowflake.id_at(window_start + index.seconds), text: "in-window-#{index}")
    end
    after_window = Fabricate(:status, account: user.account, id: Mastodon::Snowflake.id_at(window_end + 1.second), text: 'after')

    post '/api/notes/timeline', params: {
      i: token,
      sinceDate: window_start.to_i * 1000,
      untilDate: window_end.to_i * 1000,
      limit: 100,
    }, as: :json

    expect(response).to have_http_status(200)
    ids = response.parsed_body.pluck('id').map { |id| MisskeyCompat::MiId.decode(id).to_i }
    expect(ids).to match_array(in_window.map(&:id))
    expect(ids).to not_include(before_window.id, after_window.id)
  end
end
