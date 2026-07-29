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

    described_class::BLOCK_TYPE_LIMITS.each do |block_type, limit|
      it "rejects more than #{limit} #{block_type} blocks" do
        attributes = case block_type
                     when 'image'
                       { type: block_type, fileId: nil }
                     when 'note'
                       { type: block_type, note: nil }
                     when 'youtube'
                       { type: block_type, url: 'https://youtu.be/dQw4w9WgXcQ' }
                     end
        boundary_page = Fabricate.build(:page, account: account, content: Array.new(limit) { attributes })
        page = Fabricate.build(:page, account: account, content: Array.new(limit + 1) { attributes })

        expect(boundary_page).to be_valid
        expect(page).to_not be_valid
        expect(page.errors.of_kind?(:content, :invalid)).to be true
      end
    end

    it 'filters excessive external-resource blocks from legacy content when rendering' do
      page = Fabricate.build(
        :page,
        account: account,
        content: Array.new(described_class::BLOCK_TYPE_LIMITS['note'] + 2) { |index| { type: 'note', note: index.to_s } }
      )

      expect(page.renderable_content.size).to eq(described_class::BLOCK_TYPE_LIMITS['note'])
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

    it 'allows boolean spoilers on text and image blocks only', :aggregate_failures do
      supported = Fabricate.build(
        :page,
        account: account,
        content: [
          { type: 'text', text: 'hidden', spoiler: true },
          { type: 'image', fileId: nil, spoiler: false },
        ]
      )
      invalid_value = Fabricate.build(:page, account: account, content: [{ type: 'text', text: 'hidden', spoiler: 'true' }])
      unsupported_type = Fabricate.build(:page, account: account, content: [{ type: 'note', note: nil, spoiler: true }])

      expect(supported).to be_valid
      expect(invalid_value).to_not be_valid
      expect(unsupported_type).to_not be_valid
    end

    it 'accepts supported YouTube URLs and sizes, and rejects invalid values' do
      page = Fabricate.build(:page, account: account, content: [{ type: 'youtube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', size: 'large' }])

      expect(page).to be_valid

      page.content = [{ type: 'youtube', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', size: 'huge' }]

      expect(page).to_not be_valid
      expect(page.errors.of_kind?(:content, :invalid)).to be true
    end

    it 'enforces section title and YouTube URL length boundaries' do
      section = Fabricate.build(:page, account: account, content: [{ type: 'section', title: 'x' * described_class::MAX_SECTION_TITLE_LENGTH, children: [] }])
      youtube_url = 'https://youtu.be/dQw4w9WgXcQ?'.ljust(described_class::MAX_YOUTUBE_URL_LENGTH, 'x')
      youtube = Fabricate.build(:page, account: account, content: [{ type: 'youtube', url: youtube_url }])

      expect(section).to be_valid
      expect(youtube).to be_valid

      section.content.first['title'] << 'x'
      youtube.content.first['url'] << 'x'

      expect(section).to_not be_valid
      expect(youtube).to_not be_valid
    end

    it 'rejects image blocks referencing another account media' do
      media = Fabricate(:media_attachment)
      page = Fabricate.build(:page, account: account, content: [{ type: 'image', fileId: media.id.to_s }])

      expect(page).to_not be_valid
      expect(page.errors.of_kind?(:content, :invalid)).to be true
    end
  end

  describe 'creation limits' do
    it 'uses the page limit assigned to the account role' do
      role = Fabricate(:user_role, page_limit: 1)
      role_account = Fabricate(:user, role: role).account
      Fabricate(:page, account: role_account)

      page = Fabricate.build(:page, account: role_account)

      expect(page).to_not be_valid
      expect(page.errors[:base]).to include(I18n.t('pages.errors.limit', limit: 1))
    end

    it 'limits the number of pages created in one day' do
      role = Fabricate(:user_role, daily_page_limit: 1)
      role_account = Fabricate(:user, role: role).account
      Fabricate(:page, account: role_account)

      page = Fabricate.build(:page, account: role_account)

      expect(page).to_not be_valid
      expect(page.errors[:base]).to include(I18n.t('pages.errors.daily_limit', limit: 1))
    end

    it 'does not count pages created before the current day' do
      role = Fabricate(:user_role, daily_page_limit: 1)
      role_account = Fabricate(:user, role: role).account
      old_page = Fabricate(:page, account: role_account)
      old_page.update_column(:created_at, 1.day.ago)

      expect(Fabricate.build(:page, account: role_account)).to be_valid
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

    it 'includes media used as a Booklet cover' do
      media = Fabricate(:media_attachment, account: account)
      Fabricate(:page_series, account: account, cover_media_attachment: media)

      expect(MediaAttachment.referenced_by_page).to include(media)
      expect(MediaAttachment.unattached).to_not include(media)
    end
  end
end
