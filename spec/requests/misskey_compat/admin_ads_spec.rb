# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin ads and promo' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_settings] | UserRole::FLAGS[:manage_taxonomies]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:ad_params) do
    { url: 'https://ads.example', memo: 'Spring', place: 'horizontal', priority: 'middle', ratio: 1, imageUrl: 'https://ads.example/a.png', dayOfWeek: 0, isSensitive: true,
      startsAt: 1.hour.ago.to_i * 1000, expiresAt: 1.day.from_now.to_i * 1000 }
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'creates, lists, updates and deletes ads and exposes active ones in meta' do
    created = api('ad/create', **ad_params)
    ad = MisskeyAd.find(MisskeyCompat::MiId.decode(created[:id]))
    expect(created).to include(url: 'https://ads.example', memo: 'Spring', place: 'horizontal', isSensitive: true, dayOfWeek: 0)
    expect(Admin::ActionLog.where(target: ad, action: 'create')).to exist

    expect(api('ad/list', publishing: true).pluck(:id)).to eq([created[:id]])
    expect(api('ad/list', publishing: false)).to eq([])

    post '/api/meta', as: :json
    expect(response.parsed_body[:ads]).to eq([{ id: created[:id], url: 'https://ads.example', place: 'horizontal', ratio: 1, imageUrl: 'https://ads.example/a.png', dayOfWeek: 0, isSensitive: true }.stringify_keys])

    api('ad/update', id: created[:id], memo: 'Summer', dayOfWeek: 1 << ((Time.now.utc.wday + 1) % 7))
    expect(ad.reload.memo).to eq('Summer')
    post '/api/meta', as: :json
    expect(response.parsed_body[:ads]).to eq([])

    api('ad/delete', id: created[:id])
    expect(MisskeyAd.count).to eq(0)
    api('ad/delete', id: created[:id])
    expect(response.parsed_body.dig(:error, :id)).to eq('ccac9863-3a03-416e-b899-8a64041118b1')
  end

  it 'validates ad params and promotes notes once' do
    api('ad/create', **ad_params.except(:imageUrl))
    expect(response).to have_http_status(400)
    api('ad/create', **ad_params, ratio: '1')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/ratio')

    status = Fabricate(:status)
    api('promo/create', noteId: MisskeyCompat::MiId.encode(status.id), expiresAt: 1.day.from_now.to_i * 1000)
    expect(response).to have_http_status(204)
    expect(MisskeyPromoNote.find_by(status: status)).to have_attributes(account_id: status.account_id)

    api('promo/create', noteId: MisskeyCompat::MiId.encode(status.id), expiresAt: 1.day.from_now.to_i * 1000)
    expect(response.parsed_body.dig(:error, :code)).to eq('ALREADY_PROMOTED')

    api('promo/create', noteId: 'missing0000000000', expiresAt: 0)
    expect(response.parsed_body.dig(:error, :id)).to eq('ee449fbe-af2a-453b-9cae-cf2fe7c895fc')
  end
end
