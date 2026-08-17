# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Management timeline API' do
  let(:role_extra_permissions) { UserRole::EXTRA_FLAGS[:view_admin_timeline] }
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator], extra_permissions: role_extra_permissions) }
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

  it 'hides federated direct, followers-only, unlisted and limited posts' do
    hidden = %i(direct private unlisted limited).map { |visibility| status_for(visibility, local_only: false) }
    shown = %i(direct private unlisted limited).map { |visibility| status_for(visibility, local_only: true) }

    ids = timeline_ids

    expect(ids).to include(*shown.map { |status| status.id.to_s })
    expect(ids).to_not include(*hidden.map { |status| status.id.to_s })
  end

  it 'does not list cached posts authored by remote accounts' do
    remote = Fabricate(:account, domain: 'remote.example', username: 'remote-poster')
    status = Fabricate(:status, account: remote, visibility: :public, local_only: false)

    expect(timeline_ids).to_not include(status.id.to_s)
  end

  context 'when community mode is enabled after a federated install' do
    let(:role_extra_permissions) { 0 }

    it 'lets an existing administrator search legacy posts without a stored extra-permission bit' do
      legacy_public = status_for(:public, local_only: false)
      legacy_restricted = status_for(:private, local_only: false)

      expect(timeline_ids)
        .to include(legacy_public.id.to_s)
        .and not_include(legacy_restricted.id.to_s)
    end
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

  context 'with soft-hidden statuses' do
    let(:hidden) { status_for(:public, local_only: true) }

    before do
      Setting.soft_hide_deletion = true
      RpHiddenStatus.create!(status: hidden)
    end

    after do
      Setting.soft_hide_deletion = false
    end

    context 'when the viewer is the owner' do
      let(:role) { UserRole.find_by(name: 'Owner') }

      before do
        role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
      end

      it 'returns the hidden status flagged as hidden', :aggregate_failures do
        get '/api/v1/timelines/admin', headers: headers

        expect(response).to have_http_status(200)
        entry = response.parsed_body.find { |status| status[:id] == hidden.id.to_s }
        expect(entry).to be_present
        expect(entry[:rp_hidden]).to be(true)
      end
    end

    it 'hides it from a non-owner administrator', :aggregate_failures do
      get '/api/v1/timelines/admin', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to_not include(hidden.id.to_s)
    end
  end

  context 'without the management timeline permission' do
    before { role.update!(extra_permissions: 0, permissions: 0) }

    it 'refuses access' do
      get '/api/v1/timelines/admin', headers: headers

      expect(response).to have_http_status(403)
    end
  end

  context 'with the followers-only management timeline permission' do
    let(:role_extra_permissions) { UserRole::EXTRA_FLAGS[:view_followers_admin_timeline] }
    let(:role) { Fabricate(:user_role, extra_permissions: role_extra_permissions) }
    let(:follower) { Fabricate(:account, username: 'follower') }
    let(:unrelated) { Fabricate(:account, username: 'unrelated') }

    before { Fabricate(:follow, account: follower, target_account: user.account) }

    it 'lists eligible posts from the viewer followers only' do
      follower_status = Fabricate(:status, account: follower, visibility: :private, local_only: true)
      unrelated_status = Fabricate(:status, account: unrelated, visibility: :public)

      expect(timeline_ids)
        .to include(follower_status.id.to_s)
        .and not_include(unrelated_status.id.to_s)
    end

    it 'hides owner conversations authored by a follower' do
      owner = Fabricate(:user, role: UserRole.find_by(name: 'Owner')).account
      status = Fabricate(:status, account: follower, visibility: :direct, local_only: true)
      Fabricate(:mention, status: status, account: owner)

      expect(timeline_ids).to_not include(status.id.to_s)
    end
  end
end
