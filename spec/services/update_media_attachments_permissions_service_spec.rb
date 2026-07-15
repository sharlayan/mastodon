# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateMediaAttachmentsPermissionsService do
  subject(:service_call) { described_class.new.call(MediaAttachment.where(id: pointers.map(&:id)), :private) }

  let(:account) { Fabricate(:account) }
  let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
  let(:pointers) { Array.new(2) { drive_file.build_pointer(account).tap(&:save!) } }
  let(:changed_paths) { [] }

  before do
    allow(FileUtils).to receive(:chmod) { |_mask, path| changed_paths << path }
  end

  it 'changes each physical Drive file permission once for duplicate pointers' do
    pointers
    changed_paths.clear
    service_call

    expect(changed_paths).to contain_exactly(drive_file.file.path(:original), drive_file.file.path(:small))
    expect(changed_paths).to_not include(pointers.first.file.path(:original))
  end
end
