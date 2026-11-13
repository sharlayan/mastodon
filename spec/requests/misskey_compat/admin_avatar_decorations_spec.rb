# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin avatar decorations' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_custom_emojis]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before do
    Setting.misskey_compat_enabled = true
    stub_request(:get, 'https://images.example/ring.png').to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').binread, headers: { 'Content-Type' => 'image/png' })
  end

  after { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/avatar-decorations/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'creates, lists, updates and deletes local decorations through Sharlayan avatar decorations' do
    required = Fabricate(:user_role, position: 10)
    created = api('create', name: 'Ring', description: 'Shiny', url: 'https://images.example/ring.png', category: 'Rings', roleIdsThatCanBeUsedThisDecoration: [MisskeyCompat::MiId.encode(required.id)])
    decoration = AvatarDecoration.find(MisskeyCompat::MiId.decode(created[:id]))

    expect(created).to include(name: 'Ring', description: 'Shiny', category: 'Rings', updatedAt: nil, roleIdsThatCanBeUsedThisDecoration: [MisskeyCompat::MiId.encode(required.id)])
    expect(decoration).to have_attributes(approved: true, host: nil, required_role_id: required.id, image_file_name: be_present)
    expect(api('list').pluck(:id)).to eq([created[:id]])

    api('update', id: created[:id], name: 'Ring 2', roleIdsThatCanBeUsedThisDecoration: [], category: nil)
    expect(response).to have_http_status(204)
    expect(decoration.reload).to have_attributes(name: 'Ring 2', required_role_id: nil, category_id: nil)

    api('delete', id: created[:id])
    expect(AvatarDecoration.exists?(decoration.id)).to be(false)
    expect(Admin::ActionLog.where(target_type: 'AvatarDecoration').pluck(:action)).to contain_exactly('create', 'update', 'destroy')
  end

  it 'rejects multiple roles, remote updates and missing decorations' do
    roles = Fabricate.times(2, :user_role).map { |r| MisskeyCompat::MiId.encode(r.id) }
    api('create', name: 'Ring', description: '', url: 'https://images.example/ring.png', roleIdsThatCanBeUsedThisDecoration: roles)
    expect(response).to have_http_status(400)

    remote = Fabricate(:avatar_decoration, host: 'remote.example', remote_id: 'r1')
    api('update', id: MisskeyCompat::MiId.encode(remote.id), name: 'x')
    expect(response).to have_http_status(403)

    api('delete', id: 'missing0000000000')
    expect(response).to have_http_status(404)
  end
end
