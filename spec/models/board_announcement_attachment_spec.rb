# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncementAttachment, :attachment_processing do
  describe 'file content type validation' do
    it 'allows image attachments' do
      attachment = described_class.new(file: attachment_fixture('attachment.jpg'))

      expect(attachment).to be_valid
      expect(attachment).to be_image
    end

    it 'allows audio attachments' do
      attachment = described_class.new(file: attachment_fixture('boop.ogg'))

      expect(attachment).to be_valid
      expect(attachment).to be_file
    end

    it 'allows archive attachments' do
      attachment = described_class.new(file: attachment_fixture('elite-assets.tar.gz'))

      expect(attachment).to be_valid
      expect(attachment).to be_file
    end

    it 'rejects other file types' do
      attachment = described_class.new(file: attachment_fixture('custom_filters.json'))

      expect(attachment).to_not be_valid
      expect(attachment.errors[:file_content_type]).to be_present
    end
  end
end
