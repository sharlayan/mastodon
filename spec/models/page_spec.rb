# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Page do
  let(:account) { Fabricate(:account) }

  describe 'content validation' do
    it 'accepts content at the block-count boundary' do
      page = Fabricate.build(:page, account: account, content: Array.new(described_class::MAX_BLOCKS) { { type: 'text', text: 'x' } })

      expect(page).to be_valid
    end

    it 'rejects too many blocks' do
      page = Fabricate.build(:page, account: account, content: Array.new(described_class::MAX_BLOCKS + 1) { { type: 'text', text: 'x' } })

      expect(page).to_not be_valid
      expect(page.errors.of_kind?(:content, :invalid)).to be true
    end

    it 'rejects content nested beyond the depth limit' do
      content = { type: 'section', title: 'x', children: [] }
      root = content
      described_class::MAX_BLOCK_DEPTH.times do
        child = { type: 'section', title: 'x', children: [] }
        content[:children] = [child]
        content = child
      end

      page = Fabricate.build(:page, account: account, content: [root])

      expect(page).to_not be_valid
    end

    it 'rejects oversized block text' do
      page = Fabricate.build(:page, account: account, content: [{ type: 'text', text: 'x' * (described_class::MAX_TEXT_LENGTH + 1) }])

      expect(page).to_not be_valid
    end

    it 'accepts supported YouTube URLs and sizes, and rejects invalid values' do
      page = Fabricate.build(:page, account: account, content: [{ type: 'youtube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', size: 'large' }])

      expect(page).to be_valid

      page.content = [{ type: 'youtube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', size: 'huge' }]

      expect(page).to_not be_valid
      expect(page.errors.of_kind?(:content, :invalid)).to be true
    end

    it 'rejects image blocks referencing another account media' do
      media = Fabricate(:media_attachment)
      page = Fabricate.build(:page, account: account, content: [{ type: 'image', fileId: media.id.to_s }])

      expect(page).to_not be_valid
      expect(page.errors.of_kind?(:content, :invalid)).to be true
    end
  end

  describe '.referenced_by_page isolation' do
    it 'does not pin media through a page owned by another account' do
      media = Fabricate(:media_attachment)
      page = Fabricate(:page, account: account)
      page.update_column(:content, [{ type: 'image', fileId: media.id.to_s }])

      expect(MediaAttachment.referenced_by_page).to_not include(media)
      expect(MediaAttachment.unattached).to include(media)
    end
  end
end
