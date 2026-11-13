# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin roles' do
  let(:manager_role) { Fabricate(:user_role, name: 'Manager', permissions: UserRole::FLAGS[:manage_roles] | UserRole::FLAGS[:manage_users], position: 100) }
  let(:manager)      { Fabricate(:user, role: manager_role) }
  let(:token)        { MisskeyCompat::MiAuth.issue_native_token(manager).token }
  let!(:helper_role) { Fabricate(:user_role, name: 'Helper', color: '#ff0000', highlighted: true, permissions: UserRole::FLAGS[:invite_users], position: 5, drive_quota: 50) }
  let(:member)       { Fabricate(:user) }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def mid(id)
    MisskeyCompat::MiId.encode(id)
  end

  it 'lists and shows roles with mapped Misskey policies' do
    Fabricate(:user, role: helper_role)

    post '/api/admin/roles/list', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:name).grep(/\A(Manager|Helper)\z/)).to eq(%w(Manager Helper))
    expect(response.parsed_body.last).to include(id: mid(helper_role.id), color: '#ff0000', target: 'manual', asBadge: true, isModerator: false, isAdministrator: false, displayOrder: 5, usersCount: 1)
    expect(response.parsed_body.last[:policies]).to include(
      canInvite: { useDefault: false, priority: 0, value: true },
      driveCapacityMb: { useDefault: false, priority: 0, value: 50 },
      gtlAvailable: { useDefault: true, priority: 0, value: true }
    )

    post '/api/admin/roles/show', params: { i: token, roleId: mid(manager_role.id) }, as: :json
    expect(response.parsed_body).to include(name: 'Manager', isModerator: true, usersCount: 1)

    post '/api/admin/roles/show', params: { i: token, roleId: mid(UserRole::EVERYONE_ROLE_ID) }, as: :json
    expect(response).to have_http_status(400)
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_ROLE', id: '07dc7d34-c0d8-49b7-96c6-db3ce64ee0b3')
  end

  it 'creates, updates and deletes roles through Mastodon role validation and audit logs' do
    post '/api/admin/roles/create', params: {
      i: token, name: 'Reviewer', description: 'ignored', color: '#00ff00', iconUrl: nil, target: 'manual', condFormula: {},
      isPublic: true, isModerator: false, isAdministrator: false, asBadge: true, canEditMembersByModerator: false, displayOrder: 7,
      policies: { canInvite: { useDefault: false, priority: 0, value: true }, driveCapacityMb: { useDefault: false, priority: 0, value: 20 } }
    }, as: :json

    role = UserRole.find_by!(name: 'Reviewer')
    expect(role).to have_attributes(color: '#00ff00', highlighted: true, position: 7, drive_quota: 20, permissions: UserRole::FLAGS[:invite_users])
    expect(response.parsed_body).to include(id: mid(role.id), name: 'Reviewer', description: '')

    post '/api/admin/roles/update', params: { i: token, roleId: mid(role.id), name: 'Renamed', asBadge: false, policies: { canInvite: { useDefault: true, priority: 0, value: false } } }, as: :json
    expect(response).to have_http_status(204)
    expect(role.reload).to have_attributes(name: 'Renamed', highlighted: false, permissions: 0)

    post '/api/admin/roles/update', params: { i: token, roleId: mid(role.id), isAdministrator: true }, as: :json
    expect(response).to have_http_status(400)
    expect(role.reload.administrator?).to be(false)

    post '/api/admin/roles/create', params: { i: token, name: 'Auto', target: 'conditional' }, as: :json
    expect(response).to have_http_status(400)

    post '/api/admin/roles/delete', params: { i: token, roleId: mid(role.id) }, as: :json
    expect(response).to have_http_status(204)
    expect(UserRole.where(id: role.id)).to be_empty
    expect(Admin::ActionLog.where(account: manager.account, target_type: 'UserRole').pluck(:action)).to contain_exactly('create', 'update', 'destroy')
  end

  it 'assigns and unassigns the single Mastodon role of a user and lists role members' do
    post '/api/admin/roles/assign', params: { i: token, roleId: mid(helper_role.id), userId: mid(member.account_id) }, as: :json

    expect(response).to have_http_status(204)
    expect(member.reload.role_id).to eq(helper_role.id)
    expect(Admin::ActionLog.where(action: 'change_role', target: member)).to exist

    post '/api/admin/roles/users', params: { i: token, roleId: mid(helper_role.id) }, as: :json
    expect(response.parsed_body.sole).to include(id: mid(member.id), expiresAt: nil, user: a_hash_including(id: mid(member.account_id), username: member.account.username))

    post '/api/admin/roles/assign', params: { i: token, roleId: mid(helper_role.id), userId: mid(member.account_id) }, as: :json
    expect(response).to have_http_status(500)

    post '/api/admin/roles/assign', params: { i: token, roleId: mid(manager_role.id), userId: mid(member.account_id), expiresAt: 1.day.from_now.to_i * 1000 }, as: :json
    expect(response).to have_http_status(400)
    expect(member.reload.role_id).to eq(helper_role.id)

    post '/api/admin/roles/unassign', params: { i: token, roleId: mid(Fabricate(:user_role, position: 3).id), userId: mid(member.account_id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NOT_ASSIGNED')

    post '/api/admin/roles/unassign', params: { i: token, roleId: mid(helper_role.id), userId: mid(member.account_id) }, as: :json
    expect(response).to have_http_status(204)
    expect(member.reload.role_id).to be_nil
  end

  it 'refuses role changes the Mastodon role hierarchy does not allow' do
    owner = Fabricate(:user, role: Fabricate(:user_role, name: 'Owner', permissions: UserRole::FLAGS[:administrator], position: 1000))

    post '/api/admin/roles/assign', params: { i: token, roleId: mid(helper_role.id), userId: mid(owner.account_id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'ACCESS_DENIED', id: '25b5bc31-dc79-4ebd-9bd2-c84978fd052c')

    post '/api/admin/roles/assign', params: { i: token, roleId: mid(owner.role_id), userId: mid(member.account_id) }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
    expect(member.reload.role_id).to be_nil

    post '/api/admin/roles/assign', params: { i: token, roleId: mid(helper_role.id), userId: mid(Fabricate(:account, domain: 'remote.example').id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER', id: '558ea170-f653-4700-94d0-5a818371d0df')

    post '/api/admin/roles/create', params: { i: MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user)).token, name: 'X' }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'ROLE_PERMISSION_DENIED', id: 'c3d38592-54c0-429d-be96-5636b0431a61')
  end

  it 'maps default policies onto the everyone role and server drive quota' do
    settings_manager = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_roles] | UserRole::FLAGS[:manage_settings] | UserRole::FLAGS[:invite_users], position: 50))
    settings_token = MisskeyCompat::MiAuth.issue_native_token(settings_manager).token
    everyone = UserRole.everyone
    everyone.update!(permissions: 0)

    post '/api/admin/roles/update-default-policies', params: { i: settings_token, policies: { canInvite: true, driveCapacityMb: 300 } }, as: :json

    expect(response).to have_http_status(204)
    expect(everyone.reload.can?(:invite_users)).to be(true)
    expect(Setting.drive_quota).to eq(300)

    post '/api/admin/roles/update-default-policies', params: { i: token, policies: { driveCapacityMb: 10 } }, as: :json
    expect(response).to have_http_status(403)
    expect(Setting.drive_quota).to eq(300)

    post '/api/admin/roles/update-default-policies', params: { i: settings_token, policies: 'x' }, as: :json
    expect(response).to have_http_status(400)
  end
end
