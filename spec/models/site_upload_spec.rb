# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SiteUpload do
  describe '#cache_key' do
    let(:site_upload) { described_class.new(var: 'var') }

    it 'returns cache_key' do
      expect(site_upload.cache_key).to eq 'site_uploads/var'
    end
  end

  describe 'logo processing', :attachment_processing do
    it 'center-crops icon logos to a square without reducing the shorter side' do
      upload = described_class.create!(var: 'logo_icon', file: Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', '600x400.png'), 'image/png'))

      expect(FastImage.size(upload.file.path)).to eq [400, 400]
    end

    it 'preserves the original dimensions of wordmarks' do
      upload = described_class.create!(var: 'logo_wordmark_dark', file: Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', '600x400.png'), 'image/png'))

      expect(FastImage.size(upload.file.path)).to eq [600, 400]
    end

    it 'preserves animated wordmarks without cropping' do
      upload = described_class.create!(var: 'logo_wordmark_light', file: Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif'), 'image/gif'))

      expect(FastImage.size(upload.file.path)).to eq [128, 128]
    end
  end
end
