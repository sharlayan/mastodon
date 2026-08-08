# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Federation universe' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  before do
    Setting.federation_instance_edges_enabled = true
  end

  after do
    Setting.federation_instance_edges_enabled = false
  end

  it 'returns strongest observed relationships without lines entering the local server' do
    InstanceMetadata.create!(domain: 'near.example', instance_name: 'Near', software: 'mastodon', local_users_count: 120, local_posts_count: 4_500)
    UnavailableDomain.create!(domain: 'near.example')
    FederationInstanceEdge.create!(source_domain: nil, target_domain: 'near.example', reblogs_count: 8)
    FederationInstanceEdge.create!(source_domain: 'near.example', target_domain: nil, replies_count: 50)
    FederationInstanceEdge.create!(source_domain: 'near.example', target_domain: 'far.example', quotes_count: 3)

    get '/api/v1/federation_universe', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body['nodes']).to include(
      include('domain' => 'near.example', 'name' => 'Near', 'users' => 120, 'posts' => 4_500, 'gone' => true),
      include('domain' => 'far.example', 'gone' => false)
    )
    expect(response.parsed_body['edges']).to contain_exactly(
      include('source' => Rails.configuration.x.local_domain, 'target' => 'near.example', 'interactions' => 8),
      include('source' => 'near.example', 'target' => 'far.example', 'interactions' => 3)
    )
  end

  it 'is unavailable when aggregation is disabled' do
    Setting.federation_instance_edges_enabled = false

    get '/api/v1/federation_universe', headers: headers

    expect(response).to have_http_status(404)
  end

  it 'requires a signed-in user' do
    get '/api/v1/federation_universe'

    expect(response).to have_http_status(401)
  end
end
