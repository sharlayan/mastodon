# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/show-partial-bulk endpoint' do
  let(:user) { Fabricate(:user) }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:public_status) { Fabricate(:status, text: 'public') }
  let(:private_status) { Fabricate(:status, text: 'private', visibility: :private) }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  def mi(id)
    MisskeyCompat::MiId.encode(id)
  end

  it 'returns current reactions for visible notes only' do
    remote_emoji = Fabricate(:custom_emoji, shortcode: 'blobcat', domain: 'remote.example')
    Fabricate(:status_reaction, status: public_status, name: '👍', custom_emoji: nil)
    Fabricate(:status_reaction, status: public_status, name: '👍', custom_emoji: nil)
    Fabricate(:status_reaction, status: public_status, name: 'blobcat', custom_emoji: remote_emoji)
    Fabricate(:status_reaction, status: private_status, name: '👍', custom_emoji: nil)

    post '/api/notes/show-partial-bulk', params: { noteIds: [mi(public_status.id), mi(private_status.id), mi(999_999_999)] }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(1)

    item = response.parsed_body.first
    expect(item.keys).to contain_exactly('id', 'reactions', 'reactionEmojis')
    expect(item['id']).to eq(mi(public_status.id))
    expect(item['reactions']).to eq('👍' => 2, ':blobcat@remote.example:' => 1)
    expect(item['reactionEmojis'].keys).to eq(['blobcat@remote.example'])
  end

  it 'includes private notes the authenticated viewer may see' do
    user.account.follow!(private_status.account)

    post '/api/notes/show-partial-bulk', params: { i: read_token, noteIds: [mi(private_status.id)] }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck('id')).to eq([mi(private_status.id)])
    expect(response.parsed_body.first['reactions']).to eq({})
  end

  it 'rejects an empty, oversized, or missing id list' do
    post '/api/notes/show-partial-bulk', params: { noteIds: [] }, as: :json

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')

    post '/api/notes/show-partial-bulk', params: { noteIds: Array.new(101) { |index| mi(index + 1) } }, as: :json

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')

    post '/api/notes/show-partial-bulk', params: {}, as: :json

    expect(response).to have_http_status(400)
  end
end
