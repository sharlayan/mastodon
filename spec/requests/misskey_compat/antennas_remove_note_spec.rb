# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat antennas/remove-note endpoint' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:antenna) { Fabricate(:antenna, account: user.account) }
  let(:status) { Fabricate(:status) }

  before do
    Setting.antenna_enabled = true
    Setting.misskey_compat_enabled = true
    FeedManager.instance.push_to_antenna(antenna, status)
  end

  after do
    Setting.antenna_enabled = true
    Setting.misskey_compat_enabled = false
  end

  it 'removes the note from the owned antenna feed' do
    post '/api/antennas/remove-note', params: {
      i: token,
      antennaId: MisskeyCompat::MiId.encode(antenna.id),
      noteId: MisskeyCompat::MiId.encode(status.id),
    }, as: :json

    expect(response).to have_http_status(204)
    expect(AntennaFeed.new(antenna).get(10)).to_not include(status)
  end

  it 'does not allow removing a note from another account antenna' do
    other_antenna = Fabricate(:antenna)

    post '/api/antennas/remove-note', params: {
      i: token,
      antennaId: MisskeyCompat::MiId.encode(other_antenna.id),
      noteId: MisskeyCompat::MiId.encode(status.id),
    }, as: :json

    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_ANTENNA')
  end
end
