# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransferDriveFileToMediaAttachmentsService, :attachment_processing do
  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: account) }

  it 'transfers an image that has a custom thumbnail without carrying the thumbnail' do
    drive_file = account.drive_files.create!(file: attachment_fixture('attachment.jpg'), thumbnail: attachment_fixture('emojo.png'))
    pointer = drive_file.build_pointer(account).tap { |media| media.update!(status: status) }

    expect(described_class.new.call(drive_file)).to eq(1)

    expect(pointer.reload).to have_attributes(drive_file_id: nil, status_id: status.id, thumbnail_file_name: nil)
    expect(DriveFile).to_not exist(drive_file.id)
  end
end
