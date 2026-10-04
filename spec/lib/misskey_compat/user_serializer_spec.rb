# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::UserSerializer do
  before do
    Setting.avatar_decorations_enabled = true
    Setting.avatar_decorations_local_only_view = false
  end

  after do
    Setting.avatar_decorations_enabled = false
    Setting.avatar_decorations_local_only_view = false
  end

  it 'preserves detailed fields, decorations, relationships and pin order when batching accounts' do
    viewer = Fabricate(:user).account
    local = Fabricate(:user).account
    remote = Fabricate(:account, domain: 'remote.example')
    decoration = Fabricate(:avatar_decoration)
    remote.update!(avatar_decorations: [{ 'id' => decoration.id, 'angle' => 0.25, 'flip_h' => true, 'scale' => 1.2 }])
    Fabricate(:account_note, account: viewer, target_account: remote, comment: 'private memo')
    Fabricate(:follow, account: viewer, target_account: remote, show_reblogs: false)
    Fabricate(:follow_request, account: local, target_account: viewer)
    older = Fabricate(:status, account: remote, visibility: :public)
    newer = Fabricate(:status, account: remote, visibility: :unlisted)
    Fabricate(:status_pin, account: remote, status: older, created_at: 1.day.ago)
    Fabricate(:status_pin, account: remote, status: newer)
    accounts = [remote, local]
    expected = accounts.map { |account| described_class.serialize(account, detailed: true, viewer: viewer) }

    collection = MisskeyCompat::UserCollectionContext.for(accounts, viewer: viewer)
    actual = accounts.map { |account| described_class.serialize(account, detailed: true, viewer: viewer, relationships: collection.relationships, collection: collection) }

    expect(actual).to eq(expected)
    expect(actual.first[:avatarDecorations]).to contain_exactly(include(id: MisskeyCompat::MiId.encode(decoration.id), angle: 0.25, flipH: true))
    expect(actual.first[:pinnedNoteIds]).to eq([newer, older].map { |status| MisskeyCompat::MiId.encode(status.id) })
  end
end
