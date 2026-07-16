# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::DriveFileResolver, :attachment_processing do
  let(:account) { Fabricate(:account) }
  let(:media) { account.media_attachments.create!(file: attachment_fixture('attachment.jpg')) }

  it 'rejects an id shared by a regular attachment and a DriveFile' do
    DriveFile.insert_all!([{
      id: media.id,
      account_id: account.id,
      file_content_type: 'image/jpeg',
      file_file_name: 'collision.jpg',
      file_file_size: 1,
      storage_file_size: 1,
      sha256: SecureRandom.hex(32),
      type: DriveFile.types[:image],
      sensitive: false,
      created_at: Time.current,
      updated_at: Time.current,
    }])

    expect do
      described_class.new.call(account: account, file_ids: [media.id], allow_drive_files: true)
    end.to raise_error(described_class::AmbiguousFileError)
  end

  it 'does not resolve DriveFiles while the server Drive feature is disabled' do
    drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    expect do
      described_class.new.call(account: account, file_ids: [drive_file.id], allow_drive_files: false)
    end.to raise_error(described_class::NoSuchFileError)
  end

  it 'validates every id before creating DriveFile pointers' do
    drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    expect do
      described_class.new.call(account: account, file_ids: [drive_file.id, 999_999], allow_drive_files: true)
    end.to raise_error(described_class::NoSuchFileError)
      .and(not_change { account.media_attachments.where.not(drive_file_id: nil).count })
  end

  it 'removes newly-created pointers when the consumer fails' do
    drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    expect do
      described_class.new.with_resolved(account: account, file_ids: [drive_file.id], allow_drive_files: true) do
        raise Mastodon::ValidationError, 'invalid post'
      end
    end.to raise_error(Mastodon::ValidationError)
      .and(not_change { account.media_attachments.where.not(drive_file_id: nil).count })
  end
end
