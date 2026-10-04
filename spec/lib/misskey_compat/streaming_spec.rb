# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::Streaming do
  let(:broadcast_redis) { instance_double(Redis) }
  let(:account) { instance_double(Account, id: 7) }
  let(:status) { instance_double(Status) }

  before do
    Setting.misskey_compat_enabled = true
  end

  after { Setting.misskey_compat_enabled = false }

  describe '.broadcast_note' do
    it 'does not load the viewer before the subscription gate' do
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:timeline:7').and_return(false)
      allow(Account).to receive(:find_by)
      allow(MisskeyCompat::NoteSerializer).to receive(:serialize)

      described_class.broadcast_note(broadcast_redis, 'timeline:7', status, current_account_id: account.id)

      expect(Account).to_not have_received(:find_by)
      expect(MisskeyCompat::NoteSerializer).to_not have_received(:serialize)
    end

    it 'loads the viewer after the subscription gate' do
      payload = { id: 'note' }
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:timeline:7').and_return(true)
      allow(Account).to receive(:find_by).with(id: account.id).and_return(account)
      allow(MisskeyCompat::NoteSerializer).to receive(:serialize).with(status, current_account: account).and_return(payload)
      allow(broadcast_redis).to receive(:publish)

      described_class.broadcast_note(broadcast_redis, 'timeline:7', status, current_account_id: account.id)

      expect(broadcast_redis).to have_received(:publish).with('misskey:timeline:7', JSON.generate({ event: 'note', payload: payload }))
    end
  end

  describe '.broadcast_drive_file' do
    let(:drive_file) { instance_double(DriveFile) }

    it 'does not serialize when compatibility is disabled' do
      Setting.misskey_compat_enabled = false
      allow(MisskeyCompat::DriveFileSerializer).to receive(:serialize)

      described_class.broadcast_drive_file(broadcast_redis, account, drive_file, 'fileUpdated')

      expect(MisskeyCompat::DriveFileSerializer).to_not have_received(:serialize)
    end

    it 'does not serialize before the subscription gate' do
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:drive:7').and_return(false)
      allow(MisskeyCompat::DriveFileSerializer).to receive(:serialize)

      described_class.broadcast_drive_file(broadcast_redis, account, drive_file, 'fileUpdated')

      expect(MisskeyCompat::DriveFileSerializer).to_not have_received(:serialize)
    end

    it 'serializes and publishes after the subscription gate' do
      body = { id: 'file' }
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:drive:7').and_return(true)
      allow(MisskeyCompat::DriveFileSerializer).to receive(:serialize).with(drive_file).and_return(body)
      allow(broadcast_redis).to receive(:publish)

      described_class.broadcast_drive_file(broadcast_redis, account, drive_file, 'fileUpdated')

      expect(broadcast_redis).to have_received(:publish).with('misskey:drive:7', JSON.generate({ event: 'drive', payload: { type: 'fileUpdated', body: body } }))
    end

    it 'contains serializer failures' do
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:drive:7').and_return(true)
      allow(MisskeyCompat::DriveFileSerializer).to receive(:serialize).and_raise(StandardError, 'broken file')
      allow(Rails.logger).to receive(:warn)

      expect { described_class.broadcast_drive_file(broadcast_redis, account, drive_file, 'fileUpdated') }.to_not raise_error
    end

    it 'publishes a bare MiId for file deletion' do
      file_id = 9
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:drive:7').and_return(true)
      allow(broadcast_redis).to receive(:publish)
      allow(MisskeyCompat::DriveFileSerializer).to receive(:serialize)

      described_class.broadcast_drive_file(broadcast_redis, account, file_id, 'fileDeleted')

      expect(MisskeyCompat::DriveFileSerializer).to_not have_received(:serialize)
      expect(broadcast_redis).to have_received(:publish).with('misskey:drive:7', JSON.generate({ event: 'drive', payload: { type: 'fileDeleted', body: MisskeyCompat::MiId.encode(file_id) } }))
    end
  end

  describe '.broadcast_drive_folder' do
    let(:drive_folder) { instance_double(DriveFolder) }

    it 'does not serialize before the subscription gate' do
      allow(broadcast_redis).to receive(:exists?).with('subscribed:misskey:drive:7').and_return(false)
      allow(MisskeyCompat::DriveFolderSerializer).to receive(:serialize)

      described_class.broadcast_drive_folder(broadcast_redis, account, drive_folder, 'folderUpdated')

      expect(MisskeyCompat::DriveFolderSerializer).to_not have_received(:serialize)
    end
  end
end
