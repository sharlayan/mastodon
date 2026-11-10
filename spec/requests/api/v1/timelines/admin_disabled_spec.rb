# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Management timeline while its gate is off' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: nil, OC_ADMIN_TIMELINE_OPTION: nil) do
      Rails.application.reload_routes!
      example.run
    end

    Rails.application.reload_routes!
  end

  it 'leaves the routes and helper unregistered and answers 404' do
    expect(Rails.application.routes.routes.map { |route| route.path.spec.to_s })
      .to_not include(a_string_matching(%r{timelines/admin}))
    expect(Rails.application.routes.url_helpers).to_not respond_to(:api_v1_timelines_admin_path)

    get '/api/v1/timelines/admin', headers: headers

    expect(response).to have_http_status(404)
  end

  it 'does not prepend the management timeline fan-out' do
    expect(FanOutOnWriteService.ancestors).to_not include(Sharlayan::AdminTimelineFanOut::FanOut)
    expect(RemoveStatusService.ancestors).to_not include(Sharlayan::AdminTimelineFanOut::Remove)
  end
end
