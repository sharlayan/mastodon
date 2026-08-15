# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Status detail access from the management timeline' do
  let(:owner_role) { UserRole.find_by(name: 'Owner') }
  let(:owner)      { Fabricate(:user, role: owner_role) }
  let(:viewer_role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports], extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline]) }
  let(:viewer)     { Fabricate(:user, role: viewer_role) }
  let(:author)     { Fabricate(:account, username: 'author') }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') do
      Rails.application.reload_routes!
      example.run
    end

    Rails.application.reload_routes!
  end

  def headers_for(user)
    token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses')
    { 'Authorization' => "Bearer #{token.token}" }
  end

  def timeline_ids_for(user)
    get '/api/v1/timelines/admin', headers: headers_for(user)
    expect(response).to have_http_status(200)
    response.parsed_body.pluck(:id)
  end

  def detail_status_for(user, status)
    get "/api/v1/statuses/#{status.id}", headers: headers_for(user)
    response.status
  end

  context 'with a direct status authored by an owner' do
    let!(:status) { Fabricate(:status, account: owner.account, visibility: :direct, local_only: true) }

    it 'keeps it out of both the timeline and the detail view for a privilege holder', :aggregate_failures do
      expect(timeline_ids_for(viewer)).to_not include(status.id.to_s)
      expect(detail_status_for(viewer, status)).to eq(404)
    end

    it 'lets the owner read it from both entry points', :aggregate_failures do
      expect(timeline_ids_for(owner)).to include(status.id.to_s)
      expect(detail_status_for(owner, status)).to eq(200)
    end
  end

  context 'with a direct status mentioning an owner' do
    let!(:status) { Fabricate(:status, account: author, visibility: :direct, local_only: true) }

    before { Fabricate(:mention, status: status, account: owner.account) }

    it 'keeps it out of both the timeline and the detail view for a privilege holder', :aggregate_failures do
      expect(timeline_ids_for(viewer)).to_not include(status.id.to_s)
      expect(detail_status_for(viewer, status)).to eq(404)
    end

    it 'lets the owner read it from both entry points', :aggregate_failures do
      expect(timeline_ids_for(owner)).to include(status.id.to_s)
      expect(detail_status_for(owner, status)).to eq(200)
    end
  end

  context 'with a direct status between two ordinary accounts' do
    let(:other) { Fabricate(:account, username: 'other') }
    let!(:status) { Fabricate(:status, account: author, visibility: :direct, local_only: true) }

    before { Fabricate(:mention, status: status, account: other) }

    it 'is readable from both entry points by a privilege holder', :aggregate_failures do
      expect(timeline_ids_for(viewer)).to include(status.id.to_s)
      expect(detail_status_for(viewer, status)).to eq(200)
    end
  end

  context 'with a local-only followers-only status' do
    let!(:status) { Fabricate(:status, account: author, visibility: :private, local_only: true) }

    it 'is readable from both entry points by a privilege holder', :aggregate_failures do
      expect(timeline_ids_for(viewer)).to include(status.id.to_s)
      expect(detail_status_for(viewer, status)).to eq(200)
    end
  end

  context 'without the management timeline privilege' do
    let(:stranger) { Fabricate(:user) }
    let!(:status) { Fabricate(:status, account: author, visibility: :private, local_only: true) }

    it 'refuses the detail view' do
      expect(detail_status_for(stranger, status)).to eq(404)
    end
  end
end
