# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::DriveFileSerializer, :attachment_processing do
  include RoutingHelper

  let(:account) { Fabricate(:account) }
  let(:drive_file) { DriveFile.create!(account: account, file: attachment_fixture('600x400.png')) }
  let(:pointer) { drive_file.build_pointer(account).tap(&:save!) }

  it 'serializes a Drive pointer with its own per-pointer URLs and the Drive file ID' do
    result = described_class.serialize(pointer)

    expect(result).to include(
      id: MisskeyCompat::MiId.encode(drive_file.id),
      url: full_asset_url(drive_media_url(pointer.drive_access_key, :original)),
      thumbnailUrl: full_asset_url(drive_media_url(pointer.drive_access_key, :small))
    )
    expect(result[:url]).to_not include('/system/')
    expect(result[:thumbnailUrl]).to_not include('/system/')
  end

  it 'keeps storage URLs when serializing the Drive file itself' do
    result = described_class.serialize(drive_file)

    expect(result).to include(
      id: MisskeyCompat::MiId.encode(drive_file.id),
      url: full_asset_url(drive_file.file.url(:original))
    )
  end
end
