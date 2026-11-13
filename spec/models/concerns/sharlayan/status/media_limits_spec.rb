# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Status::MediaLimits do
  it 'reads the local attachment limit from MAX_MEDIA_ATTACHMENTS within 1 to 16, defaulting to 10' do
    expect(described_class.local_media_attachments_limit({})).to eq(10)
    expect(described_class.local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '6')).to eq(6)
    expect(described_class.local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '40')).to eq(16)
    expect(described_class.local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '0')).to eq(1)
    expect(described_class.local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => 'many')).to eq(10)
    expect(described_class.local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '')).to eq(10)
  end
end
