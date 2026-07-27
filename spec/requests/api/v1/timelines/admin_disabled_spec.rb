# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Management timeline while roleplay mode is off' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  it 'does not register the API or web route' do
    expect(Rails.application.routes.routes.map { |route| route.path.spec.to_s })
      .to_not include(a_string_matching(%r{timelines/admin}))
  end

  it 'has no route helper for the timeline' do
    expect(Rails.application.routes.url_helpers).to_not respond_to(:api_v1_timelines_admin_path)
  end

  it 'answers 404 for the API path' do
    get '/api/v1/timelines/admin', headers: headers

    expect(response).to have_http_status(404)
  end

  it 'strips the roleplay-only permission from a stale role bit' do
    role.update_column(:extra_permissions, UserRole::EXTRA_FLAGS[:view_admin_timeline])

    expect(role.reload.can_extra?(:view_admin_timeline)).to be(false)
  end

  it 'does not grant the roleplay-only permission to administrators' do
    expect(role.can_extra?(:view_admin_timeline)).to be(false)
    expect(role.can_extra?(:bypass_rate_limit)).to be(true)
  end

  it 'does not prepend the management timeline fan-out' do
    expect(FanOutOnWriteService.ancestors).to_not include(Sharlayan::AdminTimelineFanOut::FanOut)
    expect(RemoveStatusService.ancestors).to_not include(Sharlayan::AdminTimelineFanOut::Remove)
  end
end
