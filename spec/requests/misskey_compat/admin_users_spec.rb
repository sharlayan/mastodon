# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin user moderation' do
  let(:admin_role)  { Fabricate(:user_role, name: 'Staff', permissions: UserRole::FLAGS.values_at(:manage_users, :manage_reports, :manage_user_access, :view_dashboard).sum, position: 100) }
  let(:moderator)   { Fabricate(:user, role: admin_role) }
  let(:token)       { MisskeyCompat::MiAuth.issue_native_token(moderator).token }
  let(:target)      { Fabricate(:user, email: 'target@example.com', confirmed_at: Time.now.utc, account_attributes: { username: 'target' }) }
  let(:target_id)   { MisskeyCompat::MiId.encode(target.account_id) }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def call(endpoint, **params)
    post "/api/admin/#{endpoint}", params: { i: token }.merge(params), as: :json
  end

  it 'shows a user with Mastodon email, notes, sign-ins, IPs and role assignment' do
    role = Fabricate(:user_role, name: 'Helper', position: 5)
    target.update!(role: role)
    Fabricate(:account_moderation_note, account: moderator.account, target_account: target.account, content: 'Watch')
    target.login_activities.create!(authentication_method: 'password', success: true, ip: '192.0.2.4', user_agent: 'TestAgent')

    call('show-user', userId: target_id)

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(
      email: 'target@example.com', emailVerified: true, isModerator: false, isSuspended: false, isSilenced: false, moderationNote: 'Watch',
      roleAssigns: [a_hash_including(roleId: MisskeyCompat::MiId.encode(role.id), expiresAt: nil)],
      roles: [a_hash_including(name: 'Helper', isAdministrator: false)],
      signins: [a_hash_including(ip: '192.0.2.4', headers: { 'user-agent': 'TestAgent' }, success: true)]
    )

    call('get-user-ips', userId: target_id)
    expect(response.parsed_body.pluck(:ip)).to include('192.0.2.4')

    call('accounts/find-by-email', email: 'TARGET@example.com')
    expect(response.parsed_body).to include(id: target_id, username: 'target')

    call('accounts/find-by-email', email: 'missing@example.com')
    expect(response.parsed_body[:error]).to include(code: 'USER_NOT_FOUND', id: 'cb865949-8af5-4062-a88c-ef55e8786d1d')

    call('show-user', userId: '999999')
    expect(response).to have_http_status(404)
  end

  it 'lists users with Misskey filters and sort orders' do
    target
    remote = Fabricate(:account, domain: 'remote.example', username: 'faraway')
    Fabricate(:account, username: 'gone', suspended_at: Time.now.utc)

    call('show-users', origin: 'remote')
    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(remote.id)])

    call('show-users', state: 'suspended')
    expect(response.parsed_body.pluck(:username)).to eq(['gone'])

    call('show-users', state: 'moderator', sort: '+lastActiveDate')
    expect(response.parsed_body.pluck(:username)).to eq([moderator.account.username])

    call('show-users', username: 'tar', hostname: nil, sort: '-createdAt')
    expect(response.parsed_body.pluck(:username)).to eq(['target'])

    call('show-users', state: 'unknown')
    expect(response).to have_http_status(400)
  end

  it 'suspends and unsuspends through Mastodon account actions' do
    call('suspend-user', userId: target_id)

    expect(response).to have_http_status(204)
    expect(target.account.reload.suspended?).to be(true)
    expect(Admin::SuspensionWorker).to have_enqueued_sidekiq_job(target.account_id)

    call('unsuspend-user', userId: target_id)
    expect(target.account.reload.suspended?).to be(false)
    expect(Admin::UnsuspensionWorker).to have_enqueued_sidekiq_job(target.account_id)
    expect(Admin::ActionLog.where(account: moderator.account, target: target.account).pluck(:action)).to contain_exactly('suspend', 'unsuspend')

    superior = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator], position: 1000))
    call('suspend-user', userId: MisskeyCompat::MiId.encode(superior.account_id))
    expect(response).to have_http_status(403)
    expect(superior.account.reload.suspended?).to be(false)
  end

  it 'resets passwords, MFA, profile images and notes with audit logs' do
    target.update!(otp_required_for_login: true, otp_secret: User.generate_otp_secret)
    target.account.update!(avatar: attachment_fixture('avatar.gif'), header: attachment_fixture('attachment.jpg'))

    call('reset-password', userId: target_id)
    password = response.parsed_body[:password]
    expect(password.length).to eq(8)
    expect(target.reload.valid_password?(password)).to be(true)

    call('unset-mfa', userId: target_id)
    call('unset-user-avatar', userId: target_id)
    call('unset-user-banner', userId: target_id)
    expect(target.reload.otp_required_for_login).to be(false)
    expect(target.account.reload).to have_attributes(avatar_file_name: nil, header_file_name: nil)

    call('update-user-note', userId: target_id, text: 'First')
    call('update-user-note', userId: target_id, text: 'First')
    expect(target.account.targeted_moderation_notes.pluck(:content)).to eq(['First'])
    expect(Admin::ActionLog.where(account: moderator.account, target: target).pluck(:action)).to contain_exactly('reset_password', 'disable_2fa', 'remove_avatar', 'remove_header')

    call('reset-password', userId: MisskeyCompat::MiId.encode(Fabricate(:account, domain: 'remote.example').id))
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER', id: 'ccafc7fe-5074-4edd-9dc0-8ef9ef6a701d')
  end

  it 'deletes unattached drive files and requires the matching Mastodon permissions' do
    drive_file = DriveFile.create!(account: target.account, file: attachment_fixture('attachment.jpg'))

    call('delete-all-files-of-a-user', userId: target_id)
    expect(response).to have_http_status(204)
    expect(DriveFile.where(id: drive_file.id)).to be_empty
    expect(Admin::ActionLog.where(action: 'destroy', target_type: 'DriveFile', target_id: drive_file.id)).to exist

    reporter_only = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports], position: 50))
    post '/api/admin/get-user-ips', params: { i: MisskeyCompat::MiAuth.issue_native_token(reporter_only).token, userId: target_id }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')

    post '/api/admin/get-user-ips', params: { i: MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user)).token, userId: target_id }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'ROLE_PERMISSION_DENIED', id: 'c3d38592-54c0-429d-be96-5636b0431a61')
  end
end
