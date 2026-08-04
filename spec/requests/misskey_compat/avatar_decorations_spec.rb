# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat avatar decorations endpoint', :attachment_processing do
  before do
    Setting.avatar_decorations_enabled = true
    Setting.avatar_decorations_federation_enabled = true
    Setting.avatar_decorations_local_only_view = false
  end

  after do
    Setting.avatar_decorations_enabled = false
    Setting.avatar_decorations_federation_enabled = false
    Setting.avatar_decorations_local_only_view = false
  end

  it 'returns only approved local decorations with MiId role restrictions' do
    role = Fabricate(:user_role)
    visible = Fabricate(:avatar_decoration, name: 'Visible', description: 'Public', required_role: role)
    Fabricate(:avatar_decoration, name: 'Pending', approved: false)
    Fabricate(:avatar_decoration, name: 'Remote', host: 'remote.example', remote_id: 'remote-decoration')

    post '/api/get-avatar-decorations', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to contain_exactly(
      include(
        id: MisskeyCompat::MiId.encode(visible.id),
        name: 'Visible',
        description: 'Public',
        roleIdsThatCanBeUsedThisDecoration: [MisskeyCompat::MiId.encode(role.id)]
      )
    )
    expect(response.parsed_body.first[:url]).to be_present
  end

  it 'returns an empty list when federation exposure is disabled' do
    Fabricate(:avatar_decoration)
    Setting.avatar_decorations_federation_enabled = false

    post '/api/get-avatar-decorations', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])
  end

  it 'returns an empty list in local-only view mode' do
    Fabricate(:avatar_decoration)
    Setting.avatar_decorations_local_only_view = true

    post '/api/get-avatar-decorations', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])
  end
end
