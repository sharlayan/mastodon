# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecoration do
  before do
    stub_request(:get, %r{\Ahttps://(example\.com|remote\.example)/})
      .to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read, headers: { 'Content-Type' => 'image/png' })
  end

  describe 'validations' do
    it 'requires a name' do
      decoration = described_class.new(name: '', image: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').open)
      expect(decoration).to_not be_valid
      expect(decoration.errors[:name]).to be_present
    end

    it 'limits name length to 256 characters' do
      decoration = described_class.new(name: 'a' * 257, image: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').open)
      expect(decoration).to_not be_valid
    end

    it 'limits description length to 2048 characters' do
      decoration = described_class.new(name: 'test', description: 'a' * 2049, image: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').open)
      expect(decoration).to_not be_valid
    end

    it 'requires image or remote URL' do
      decoration = described_class.new(name: 'test')
      expect(decoration).to_not be_valid
      expect(decoration.errors[:image]).to be_present
    end

    it 'accepts remote URL in place of image' do
      decoration = described_class.new(name: 'test', image_remote_url: 'https://example.com/deco.png', host: 'example.com', remote_id: '1')
      expect(decoration.errors[:image]).to be_blank
      expect(a_request(:get, decoration.image_remote_url)).to_not have_been_made
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

    describe '.local' do
      it 'returns only decorations with nil host' do
        expect(described_class.local).to contain_exactly(local_approved, local_pending)
      end
    end

    describe '.remote' do
      it 'returns only decorations with a host' do
        expect(described_class.remote).to contain_exactly(remote_approved, remote_pending)
      end
    end

    describe '.approved' do
      it 'returns only approved decorations' do
        expect(described_class.approved).to contain_exactly(local_approved, remote_approved)
      end
    end

    describe '.pending_approval' do
      it 'returns all unapproved decorations' do
        expect(described_class.pending_approval).to contain_exactly(local_pending, remote_pending)
      end
    end
  end

  describe '#local?' do
    it 'returns true when host is nil' do
      expect(Fabricate(:avatar_decoration, host: nil).local?).to be true
    end

    it 'returns false when host is present' do
      decoration = Fabricate(:avatar_decoration, host: 'example.com', image_remote_url: 'https://example.com/d.png', remote_id: 'x1', image: nil)
      expect(decoration.local?).to be false
    end
  end

  describe '#image_url' do
    it 'returns paperclip URL for local decorations' do
      decoration = Fabricate(:avatar_decoration)
      expect(decoration.image_url).to include('/original/')
    end

    it 'returns the remote URL until the asynchronous cache download completes' do
      decoration = Fabricate(:avatar_decoration, host: 'example.com', image_remote_url: 'https://example.com/deco.png', remote_id: 'r1', image: nil)
      expect(decoration.image_url).to eq('https://example.com/deco.png')
    end
  end

  describe '#image_static_url' do
    it 'returns static URL for local GIF decorations' do
      decoration = Fabricate(:avatar_decoration)
      decoration.image_content_type = 'image/gif'
      expect(decoration.image_static_url).to include('/static/')
    end

    it 'returns same URL as image_url for non-GIF' do
      decoration = Fabricate(:avatar_decoration)
      decoration.image_content_type = 'image/png'
      expect(decoration.image_static_url).to eq(decoration.image_url)
    end
  end
end
