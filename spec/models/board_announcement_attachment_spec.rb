# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncementAttachment, :attachment_processing do
  describe 'file content type validation' do
    it 'allows image, audio and archive attachments and rejects other file types' do
      image = described_class.new(file: attachment_fixture('attachment.jpg'))
      audio = described_class.new(file: attachment_fixture('boop.ogg'))
      archive = described_class.new(file: attachment_fixture('elite-assets.tar.gz'))
      other = described_class.new(file: attachment_fixture('custom_filters.json'))

      expect(image).to be_valid
      expect(image).to be_image
      expect(audio).to be_valid
      expect(audio).to be_file
      expect(archive).to be_valid
      expect(archive).to be_file
      expect(other).to_not be_valid
      expect(other.errors[:file_content_type]).to be_present
    end
  end
end
