# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecoration do
  before do
    stub_request(:get, %r{\Ahttps://(example\.com|remote\.example)/})
      .to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read, headers: { 'Content-Type' => 'image/png' })
  end

  describe 'validations' do
    let(:image) { Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').open }

    it 'requires a name and limits name and description lengths' do
      blank_name = described_class.new(name: '', image: image)
      long_name = described_class.new(name: 'a' * 257, image: image)
      long_description = described_class.new(name: 'test', description: 'a' * 2049, image: image)

      expect(blank_name).to_not be_valid
      expect(blank_name.errors[:name]).to be_present
      expect(long_name).to_not be_valid
      expect(long_description).to_not be_valid
    end

    it 'requires an image or accepts a remote URL in its place without downloading it' do
      missing = described_class.new(name: 'test')
      remote = described_class.new(name: 'test', image_remote_url: 'https://example.com/deco.png', host: 'example.com', remote_id: '1')

      expect(missing).to_not be_valid
      expect(missing.errors[:image]).to be_present
      expect(remote.errors[:image]).to be_blank
      expect(a_request(:get, remote.image_remote_url)).to_not have_been_made
    end

    it 'enforces remote_id uniqueness per host' do
      Fabricate(:avatar_decoration, host: 'example.com', remote_id: 'abc', image_remote_url: 'https://example.com/a.png', image: nil)
      dup = described_class.new(name: 'dup', host: 'example.com', remote_id: 'abc', image_remote_url: 'https://example.com/b.png')
      expect(dup).to_not be_valid
    end
  end

  describe 'scopes' do
    let!(:local_approved) { Fabricate(:avatar_decoration, host: nil, approved: true) }
    let!(:local_pending) { Fabricate(:avatar_decoration, host: nil, approved: false) }
    let!(:remote_approved) { Fabricate(:avatar_decoration, host: 'remote.example', approved: true, image_remote_url: 'https://remote.example/d.png', remote_id: 'r1', image: nil) }
    let!(:remote_pending) { Fabricate(:avatar_decoration, host: 'remote.example', approved: false, image_remote_url: 'https://remote.example/d2.png', remote_id: 'r2', image: nil) }

    it 'filter decorations by host and approval state' do
      expect(described_class.local).to contain_exactly(local_approved, local_pending)
      expect(described_class.remote).to contain_exactly(remote_approved, remote_pending)
      expect(described_class.approved).to contain_exactly(local_approved, remote_approved)
      expect(described_class.pending_approval).to contain_exactly(local_pending, remote_pending)
    end
  end

  describe '.visible_configs_for' do
    before { Setting.avatar_decorations_enabled = true }

    it 'hides a remote decoration whose image has not been downloaded and a local decoration that is no longer approved' do
      remote_account = Fabricate(:account, domain: 'remote.example')
      remote_decoration = Fabricate(:avatar_decoration, host: 'remote.example', remote_id: 'x', image_remote_url: 'https://remote.example/x.png', image: nil)
      remote_account.update_columns(avatar_decorations: [{ 'id' => remote_decoration.id }])
      local_account = Fabricate(:account)
      unapproved_decoration = Fabricate(:avatar_decoration, approved: false)
      local_account.update_columns(avatar_decorations: [{ 'id' => unapproved_decoration.id }])

      expect(described_class.visible_configs_for(remote_account)).to be_empty
      expect(described_class.visible_configs_for(local_account)).to be_empty
    end

    it 'hides a local decoration once the account role no longer meets its requirement' do
      role = Fabricate(:user_role, position: 100)
      user = Fabricate(:user, role: role)
      decoration = Fabricate(:avatar_decoration, required_role: role)
      user.account.update_columns(avatar_decorations: [{ 'id' => decoration.id }])

      expect(described_class.visible_configs_for(user.account)).to contain_exactly([include('id' => decoration.id), decoration])

      RequestStore.clear!
      user.update!(role: UserRole.everyone)

      expect(described_class.visible_configs_for(user.account.reload)).to be_empty
    end
  end

  describe 'local and remote image URLs' do
    it 'serves local decorations from paperclip with a static variant for GIFs' do
      decoration = Fabricate(:avatar_decoration, host: nil)

      expect(decoration.local?).to be true
      expect(decoration.image_url).to include('/original/')

      decoration.image_content_type = 'image/gif'
      expect(decoration.image_static_url).to include('/static/')

      decoration.image_content_type = 'image/png'
      expect(decoration.image_static_url).to eq(decoration.image_url)
    end

    it 'returns the remote URL for remote decorations until the asynchronous cache download completes' do
      decoration = Fabricate(:avatar_decoration, host: 'example.com', image_remote_url: 'https://example.com/deco.png', remote_id: 'r1', image: nil)

      expect(decoration.local?).to be false
      expect(decoration.image_url).to eq('https://example.com/deco.png')
    end
  end
end
