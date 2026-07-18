# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MediaAttachment, :attachment_processing do
  let(:account) { Fabricate(:account) }

  describe 'Drive pointers' do
    subject(:media_attachment) { described_class.new(account: account, drive_file_id: 123) }

    it 'accepts a local attachment without a file and generates an access key' do
      media_attachment.validate

      expect(media_attachment.errors.of_kind?(:file, :blank)).to be false
      expect(media_attachment.drive_access_key).to match(/\A[-_A-Za-z0-9]{43}\z/)
    end

    it 'keeps requiring files for ordinary local attachments' do
      ordinary_attachment = described_class.new(account: account)

      expect(ordinary_attachment).to_not be_valid
      expect(ordinary_attachment.errors.of_kind?(:file, :blank)).to be true
    end
  end

  describe 'Page references' do
    let!(:media_attachment) { Fabricate(:media_attachment, account: account) }

    it 'keeps same-account page media in use and out of the unattached scope' do
      page = Fabricate(:page, account: account)
      page.update_column(:content, [{ type: 'image', fileId: media_attachment.id.to_s }])

      expect(described_class.referenced_by_page).to include(media_attachment)
      expect(described_class.in_use).to include(media_attachment)
      expect(described_class.unattached).to_not include(media_attachment)
    end
  end
end
