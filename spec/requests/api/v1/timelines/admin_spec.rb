# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Management timeline API' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:scopes) { 'read:statuses' }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:poster) { Fabricate(:account) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') do
      Rails.application.reload_routes!
      example.run
    end

    Rails.application.reload_routes!
  end

  before do
    role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
  end

  def status_for(visibility, local_only:)
    Fabricate(:status, account: poster, visibility: visibility, local_only: local_only)
  end

  def timeline_ids
    get '/api/v1/timelines/admin', headers: headers
    expect(response).to have_http_status(200)
    response.parsed_body.pluck(:id)
  end

  it 'lists public posts whether or not they federated' do
    federated = status_for(:public, local_only: false)
    local = status_for(:public, local_only: true)

    expect(timeline_ids).to include(federated.id.to_s, local.id.to_s)
  end

  it 'hides federated direct, followers-only and unlisted posts' do
    hidden = %i(direct private unlisted).map { |visibility| status_for(visibility, local_only: false) }
    shown = %i(direct private unlisted).map { |visibility| status_for(visibility, local_only: true) }

    ids = timeline_ids

    expect(ids).to include(*shown.map { |status| status.id.to_s })
    expect(ids).to_not include(*hidden.map { |status| status.id.to_s })
  end

  it 'hides conversations a remote account takes part in' do
    remote = Fabricate(:account, domain: 'remote.example', username: 'stranger')
    mentioning = status_for(:direct, local_only: true)
    Fabricate(:mention, status: mentioning, account: remote)
    replying = Fabricate(:status, account: poster, visibility: :private, local_only: true, in_reply_to_account_id: remote.id)
    local_only_dm = status_for(:direct, local_only: true)

    ids = timeline_ids

    expect(ids).to include(local_only_dm.id.to_s)
    expect(ids).to_not include(mentioning.id.to_s, replying.id.to_s)
  end

  it 'is not reachable while either gate is disabled' do
    [
      { OC_ROLEPLAY_OPTION: 'false', OC_ADMIN_TIMELINE_OPTION: 'true' },
      { OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'false' },
    ].each do |env|
      ClimateControl.modify(**env) do
        get '/api/v1/timelines/admin', headers: headers
      end

      expect(response).to have_http_status(404)
    end
  end

  context 'without the management timeline permission' do
    before { role.update!(extra_permissions: 0, permissions: 0) }

    it 'refuses access' do
      get '/api/v1/timelines/admin', headers: headers

      expect(response).to have_http_status(403)
    end
  end
end
