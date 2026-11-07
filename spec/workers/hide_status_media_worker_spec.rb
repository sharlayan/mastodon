# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HideStatusMediaWorker do
  subject { described_class.new.perform(status.id) }

  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: account) }
  let(:service) { instance_double(UpdateMediaAttachmentsPermissionsService, call: nil) }

  before do
    allow(UpdateMediaAttachmentsPermissionsService).to receive(:new).and_return(service)
    RpHiddenStatus.create!(status: status)
  end

  it 'restricts only media owned by the status, not shared Drive files' do
    own_media = Fabricate(:media_attachment, account: account, status: status)
    drive_file = account.drive_files.create!(file: attachment_fixture('attachment.jpg'))
    drive_file.build_pointer(account).tap { |pointer| pointer.update!(status: status) }

    subject

    expect(service).to have_received(:call).with(satisfy { |scope| scope.map(&:id) == [own_media.id] }, :private)
    expect(status.rp_hidden_status.reload.media_moved).to be(true)
  end
end
