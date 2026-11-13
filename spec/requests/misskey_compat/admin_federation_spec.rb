# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin federation and relays' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_federation]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let!(:remote_account) { Fabricate(:account, domain: 'remote.example', username: 'far', inbox_url: 'https://remote.example/inbox', protocol: :activitypub) }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'suspends and unsuspends instances through Mastodon domain blocks and records notes' do
    api('federation/update-instance', host: 'Remote.Example', isSuspended: true, moderationNote: 'spam')
    block = DomainBlock.find_by(domain: 'remote.example')

    expect(response).to have_http_status(204)
    expect(block).to be_suspend
    expect(DomainBlockWorker).to have_enqueued_sidekiq_job(block.id)
    expect(InstanceModerationNote.where(domain: 'remote.example').pluck(:content)).to eq(%w(spam))

    api('federation/update-instance', host: 'remote.example', isSuspended: false, moderationNote: 'spam')
    expect(DomainBlock.exists?(domain: 'remote.example')).to be(false)
    expect(InstanceModerationNote.where(domain: 'remote.example').count).to eq(1)
    expect(Admin::ActionLog.where(target_type: 'DomainBlock').pluck(:action)).to contain_exactly('create', 'destroy')

    api('federation/update-instance', host: 'unknown.example', isSuspended: true)
    expect(response).to have_http_status(404)
  end

  it 'queues media cleanup, follower removal and metadata refresh for a host' do
    local = Fabricate(:account)
    Follow.create!(account: remote_account, target_account: local)
    media = Fabricate(:media_attachment, account: remote_account, remote_url: 'https://remote.example/a.png')

    api('federation/refresh-remote-instance-metadata', host: 'remote.example')
    expect(InstanceMetadataUpdateWorker).to have_enqueued_sidekiq_job('remote.example', 'manual')

    api('federation/delete-all-files', host: 'remote.example')
    api('federation/remove-all-following', host: 'remote.example')
    MisskeyCompatRemoteMediaCleanupWorker.drain
    MisskeyCompatRemoveDomainFollowersWorker.drain

    expect(media.reload.file).to be_blank
    expect(local.passive_relationships).to be_empty
    expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(anything, local.id, 'https://remote.example/inbox')
  end

  it 'adds, lists and removes relays through Mastodon relays' do
    created = api('relays/add', inbox: 'https://relay.example/inbox')
    expect(created).to include(inbox: 'https://relay.example/inbox', status: 'requesting')
    expect(Relay.find_by(inbox_url: 'https://relay.example/inbox')).to be_pending

    expect(api('relays/list')).to eq([created])

    api('relays/add', inbox: 'http://relay.example/inbox')
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_URL')

    api('relays/remove', inbox: 'https://relay.example/inbox')
    expect(Relay.count).to eq(0)
    expect(Admin::ActionLog.where(target_type: 'Relay').pluck(:action)).to contain_exactly('create', 'destroy')
  end

  it 'requires the federation permission' do
    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_custom_emojis]))
    api('relays/list')

    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('ROLE_PERMISSION_DENIED')
  end
end
