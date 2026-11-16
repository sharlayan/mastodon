# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin drive' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users] | UserRole::FLAGS[:manage_settings]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:owner) { Fabricate(:account) }
  let(:remote_account) { Fabricate(:account, domain: 'remote.example') }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/drive/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'lists local drive files and remote media by origin, owner, host and type' do
    drive_file = DriveFile.create!(account: owner, file: attachment_fixture('attachment.jpg'))
    remote = Fabricate(:media_attachment, account: remote_account, remote_url: 'https://remote.example/a.png')

    expect(api('files').pluck(:id)).to eq([MisskeyCompat::MiId.encode(drive_file.id)])
    expect(api('files', origin: 'remote').pluck(:id)).to eq([MisskeyCompat::MiId.encode(remote.id)])
    expect(api('files', origin: 'combined').pluck(:id)).to eq([remote, drive_file].sort_by(&:id).reverse.map { |file| MisskeyCompat::MiId.encode(file.id) })
    expect(api('files', hostname: 'remote.example').pluck(:id)).to eq([MisskeyCompat::MiId.encode(remote.id)])
    expect(api('files', userId: MisskeyCompat::MiId.encode(owner.id), type: 'image/*').sole).to include(user: include(username: owner.username), folder: nil)
    expect(api('files', type: 'video/*')).to eq([])

    shown = api('show-file', url: 'https://remote.example/a.png')
    expect(shown).to include(id: MisskeyCompat::MiId.encode(remote.id), userHost: 'remote.example', src: 'https://remote.example/a.png', requestIp: nil)
    expect(api('show-file', fileId: MisskeyCompat::MiId.encode(drive_file.id))).to include(userHost: nil, isLink: false, storedInternal: true)

    api('show-file', fileId: 'missing0000000000')
    expect(response.parsed_body.dig(:error, :id)).to eq('caf3ca38-c6e5-472e-a30c-b05377dcc240')
  end

  it 'queues orphaned media vacuum and remote media cache cleanup' do
    remote = Fabricate(:media_attachment, account: remote_account, remote_url: 'https://remote.example/b.png')
    orphan = Fabricate(:media_attachment, account: owner, created_at: 2.days.ago)
    drive_file = DriveFile.create!(account: owner, file: attachment_fixture('attachment.jpg'))

    api('cleanup')
    api('clean-remote-files')
    expect(response).to have_http_status(204)
    MisskeyCompatOrphanedMediaCleanupWorker.drain
    MisskeyCompatRemoteMediaCleanupWorker.drain

    expect(MediaAttachment.exists?(orphan.id)).to be(false)
    expect(remote.reload.file).to be_blank
    expect(DriveFile.exists?(drive_file.id)).to be(true)
  end
end
