# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchRemoteAvatarDecorationsWorker do
  subject(:worker) { described_class.new }

  let(:account) { Fabricate(:account, domain: 'remote.example') }

  before do
    Setting.avatar_decorations_enabled = true
    Setting.avatar_decorations_federation_enabled = true
  end

  it 'queues cleanup when the remote account removes its decorations' do
    decoration = Fabricate(:avatar_decoration, host: account.domain, remote_id: 'old', image_remote_url: 'https://remote.example/old.png', image: nil)
    account.update_columns(avatar_decorations: [{ id: decoration.id }])
    stub_request(:post, 'https://remote.example/api/users/show')
      .to_return(status: 200, body: { avatarDecorations: [] }.to_json)
    allow(CleanupRemoteAvatarDecorationsWorker).to receive(:enqueue)

    worker.perform(account.id)

    expect(account.reload.avatar_decorations).to be_empty
    expect(CleanupRemoteAvatarDecorationsWorker).to have_received(:enqueue).with([decoration.id])
  end

  it 'persists metadata and queues image download without fetching the image inline' do
    stub_request(:post, 'https://remote.example/api/users/show')
      .to_return(status: 200, body: { avatarDecorations: [{ id: 'new' }] }.to_json)
    stub_request(:post, 'https://remote.example/api/get-avatar-decorations')
      .to_return(status: 200, body: [{ id: 'new', name: 'New', url: 'https://remote.example/new.png' }].to_json)
    allow(RedownloadAvatarDecorationWorker).to receive(:enqueue)
    image_request = stub_request(:get, 'https://remote.example/new.png')

    worker.perform(account.id)

    decoration = AvatarDecoration.find_by!(host: account.domain, remote_id: 'new')
    expect(decoration.image_file_name).to be_blank
    expect(RedownloadAvatarDecorationWorker).to have_received(:enqueue).with(decoration.id, account_id: account.id)
    expect(image_request).to_not have_been_requested
  end
end
