# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DriveFile, :attachment_processing do
  let(:account) { Fabricate(:account) }
  let(:drive_file) { described_class.create!(account: account, file: attachment_fixture('attachment.jpg')) }

  describe '.allowed_content_types' do
    it 'always allows media types' do
      expect(described_class.allowed_content_types).to include('image/jpeg', 'video/mp4', 'audio/mpeg')
    end

    it 'allows the extensions the administrator listed' do
      Setting.drive_allowed_extensions = 'pdf, zip'

      expect(described_class.extra_extensions).to eq(%w(pdf zip))
      expect(described_class.allowed_content_types).to include('application/pdf', 'application/zip')
    end

    it 'ignores extensions whose files could be served as script or markup' do
      Setting.drive_allowed_extensions = 'html, svg, js, xml, pdf'

      expect(described_class.extra_extensions).to eq(%w(pdf))
      expect(described_class.allowed_content_types).to_not include('text/html', 'image/svg+xml', 'text/javascript')
    end
  end

  describe '#quota_storage_file_size' do
    it 'stores the total size of every processed file style' do
      file = described_class.create!(account: account, file: attachment_fixture('attachment.jpg'))
      stored_sizes = file.file.styles.keys.sum { |style| File.size(file.file.path(style)) }
      stored_sizes += File.size(file.file.path(:original)) unless file.file.styles.key?(:original)

      expect(file.storage_file_size).to eq(stored_sizes)
      expect(file.storage_file_size).to be > file.file_file_size
    end
  end

  describe 'video validation' do
    let(:file) { described_class.new(account: account, file: attachment_fixture('attachment.webm')) }

    it 'rejects video dimensions above the media attachment limit' do
      extractor = instance_double(VideoMetadataExtractor, valid?: true, width: 4000, height: 3000, frame_rate: 30)
      allow(VideoMetadataExtractor).to receive(:new).and_return(extractor)

      expect { file.valid? }.to raise_error(Mastodon::DimensionsValidationError, '4000x3000 videos are not supported')
    end

    it 'rejects frame rates above the media attachment limit' do
      extractor = instance_double(VideoMetadataExtractor, valid?: true, width: 640, height: 480, frame_rate: 121)
      allow(VideoMetadataExtractor).to receive(:new).and_return(extractor)

      expect { file.valid? }.to raise_error(Mastodon::DimensionsValidationError, '121fps videos are not supported')
    end

    it 'rejects files without a video stream' do
      extractor = instance_double(VideoMetadataExtractor, valid?: true, width: nil, frame_rate: nil)
      allow(VideoMetadataExtractor).to receive(:new).and_return(extractor)

      expect { file.valid? }.to raise_error(Mastodon::StreamValidationError, 'Video has no video stream')
    end
  end

  describe 'deduplication constraint' do
    it 'rejects the same digest for the same account' do
      drive_file.update_column(:sha256, SecureRandom.hex(32))
      attributes = drive_file.attributes.except('id', 'created_at', 'updated_at')

      expect { described_class.insert_all!([attributes]) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'folder ownership' do
    it 'rejects a folder owned by another account' do
      drive_file.folder = DriveFolder.create!(account: Fabricate(:account), name: 'Foreign')

      expect(drive_file).to_not be_valid
      expect(drive_file.errors.of_kind?(:folder_id, :invalid)).to be true
    end
  end

  describe '#attached?' do
    it 'is true for a published status attachment' do
      pointer = drive_file.build_pointer(account)
      pointer.status = Fabricate(:status, account: account)
      pointer.save!

      expect(drive_file).to be_attached
    end

    it 'is true for a scheduled status attachment' do
      pointer = drive_file.build_pointer(account)
      pointer.scheduled_status = Fabricate(:scheduled_status, account: account)
      pointer.save!

      expect(drive_file).to be_attached
    end

    it 'is true for a page image' do
      pointer = drive_file.build_pointer(account)
      pointer.save!
      Fabricate(:page, account: account, content: [{ id: 'image', type: 'image', fileId: pointer.id.to_s }])

      expect(drive_file).to be_attached
    end
  end

  describe '.orphaned' do
    it 'excludes files used by scheduled statuses' do
      pointer = drive_file.build_pointer(account)
      pointer.scheduled_status = Fabricate(:scheduled_status, account: account)
      pointer.save!

      expect(described_class.orphaned).to_not include(drive_file)
    end

    it 'excludes files used by pages' do
      pointer = drive_file.build_pointer(account)
      pointer.save!
      Fabricate(:page, account: account, eye_catching_media_attachment: pointer)

      expect(described_class.orphaned).to_not include(drive_file)
    end
  end

  describe '#destroy' do
    it 'refuses to destroy a file used by a scheduled status' do
      pointer = drive_file.build_pointer(account)
      pointer.scheduled_status = Fabricate(:scheduled_status, account: account)
      pointer.save!

      expect(drive_file.destroy).to be false
      expect(described_class).to exist(drive_file.id)
      expect(MediaAttachment).to exist(pointer.id)
    end

    it 'refuses to destroy a file used by a page' do
      pointer = drive_file.build_pointer(account)
      pointer.save!
      Fabricate(:page, account: account, content: [{ id: 'image', type: 'image', fileId: pointer.id.to_s }])

      expect(drive_file.destroy).to be false
      expect(described_class).to exist(drive_file.id)
      expect(MediaAttachment).to exist(pointer.id)
    end

    it 'destroys unattached pointers before destroying the file' do
      pointer = drive_file.build_pointer(account)
      pointer.save!

      expect { drive_file.destroy }
        .to change(described_class, :count).by(-1)
        .and change(MediaAttachment, :count).by(-1)
      expect(MediaAttachment).to_not exist(pointer.id)
    end
  end

  describe 'attach and delete concurrency', use_transactional_tests: false do
    let(:status) { Fabricate(:status, account: account) }
    let(:deletion_paused) { Queue.new }
    let(:allow_deletion) { Queue.new }
    let(:attach_started) { Queue.new }
    let(:pause_deletion) do
      paused = deletion_paused
      allowed = allow_deletion
      proc do
        paused << true
        allowed.pop
      end
    end

    before do
      drive_file
      status
      described_class.set_callback(:destroy, :before, pause_deletion)
    end

    after do
      described_class.skip_callback(:destroy, :before, pause_deletion)
      status.destroy
      account.destroy
    end

    it 'does not leave a pointer without its drive file' do
      destroy_thread = destroy_drive_file_in_thread
      deletion_paused.pop
      attach_thread = attach_drive_file_in_thread
      attach_started.pop
      allow_deletion << true
      destroy_thread.value
      attach_thread.value

      expect(described_class).to_not exist(drive_file.id)
      expect(MediaAttachment.where(drive_file_id: drive_file.id)).to be_empty
    end

    def destroy_drive_file_in_thread
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          described_class.find(drive_file.id).destroy
        end
      end
    end

    def attach_drive_file_in_thread
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          file = described_class.find(drive_file.id)
          attach_started << true
          file.with_lock do
            file.build_pointer(account).tap do |pointer|
              pointer.status = status
              pointer.save!
            end
          end
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end
  end
end
