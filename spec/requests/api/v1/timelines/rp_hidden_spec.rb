# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 RP hidden timeline' do
  let(:owner) { Fabricate(:user, role: UserRole.find_by(name: 'Owner')) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: owner.id, scopes: 'read:statuses') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:status) { Fabricate(:status) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  before do
    Setting.soft_hide_deletion = true
    RpHiddenStatus.create!(status: status)
  end

  after do
    Setting.soft_hide_deletion = false
  end

  it 'returns hidden statuses with the owner audit marker' do
    get '/api/v1/timelines/rp_hidden', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to contain_exactly(include(id: status.id.to_s, rp_hidden: true))
  end

  it 'does not return hidden statuses to a non-owner administrator' do
    admin = Fabricate(:user, role: UserRole.find_by(name: 'Admin'))
    admin_token = Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read:statuses')

    get '/api/v1/timelines/rp_hidden', headers: { 'Authorization' => "Bearer #{admin_token.token}" }

    expect(response).to have_http_status(404)
  end

  it 'requires authentication' do
    get '/api/v1/timelines/rp_hidden'

    expect(response).to have_http_status(401)
  end

  it 'is unavailable when soft-hide deletion is disabled' do
    Setting.soft_hide_deletion = false

    get '/api/v1/timelines/rp_hidden', headers: headers

    expect(response).to have_http_status(404)
  end
end
