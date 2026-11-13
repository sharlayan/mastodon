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

  it 'keeps remote edit history attachments up to the remote limit rather than the local one' do
    Setting.remote_media_attachments_limit = 16
    stub_const('Status::MEDIA_ATTACHMENTS_LIMIT', 2)
    status = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))
    attachments = Array.new(5) { Fabricate(:media_attachment, account: status.account, status: status) }
    edit = Fabricate(:status_edit, status: status, ordered_media_attachment_ids: attachments.map(&:id), media_descriptions: Array.new(5, ''))

    expect(edit.ordered_media_attachments.map(&:id)).to eq(attachments.map(&:id))

    Setting.remote_media_attachments_limit = 4

    expect(StatusEdit.find(edit.id).ordered_media_attachments.size).to eq(4)
  end
end
