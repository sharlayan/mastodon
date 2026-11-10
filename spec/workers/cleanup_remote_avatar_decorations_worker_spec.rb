# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CleanupRemoteAvatarDecorationsWorker do
  subject(:worker) { described_class.new }

  it 'deletes unreferenced remote decorations and preserves referenced ones with a single account query' do
    used = remote_decoration('used')
    orphan = remote_decoration('orphan')
    Fabricate(:account, avatar_decorations: [{ id: used.id }, { id: 1 }])

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "accounts"') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      worker.perform([used.id, orphan.id])
    end

    expect(AvatarDecoration.exists?(used.id)).to be true
    expect(AvatarDecoration.exists?(orphan.id)).to be false
    expect(queries.size).to eq 1
  end

  it 'never deletes a local decoration' do
    decoration = Fabricate(:avatar_decoration)

    expect { worker.perform([decoration.id]) }.to_not change(AvatarDecoration, :count)
  end

  def remote_decoration(id)
    Fabricate(
      :avatar_decoration,
      host: 'remote.example',
      remote_id: id,
      image_remote_url: "https://remote.example/#{id}.png",
      image: nil
    )
  end
end
