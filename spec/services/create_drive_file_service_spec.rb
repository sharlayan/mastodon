# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateDriveFileService do
  subject(:upload_again) do
    described_class.new.call(account: account, user: account.user, file: upload, **options)
  end

  let(:account) { Fabricate(:user).account }
  let(:folder) { account.drive_folders.create!(name: 'Uploads') }
  let(:upload) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', 'attachment.jpg'), 'image/jpeg') }
  let(:options) { {} }
  let!(:existing) do
    described_class.new.call(
      account: account, user: account.user, file: upload,
      folder_id: folder.id, folder_id_provided: true,
      description: 'Original description', sensitive: true
    )
  end

  it 'preserves sensitive metadata when it is omitted from or nil in a duplicate upload' do
    expect(upload_again).to eq(existing)
    expect(existing.reload).to be_sensitive

    described_class.new.call(account: account, user: account.user, file: upload, sensitive: nil)

    expect(existing.reload).to be_sensitive
  end

  context 'when sensitive is explicitly false' do
    let(:options) { { sensitive: false, description: '', folder_id: '', folder_id_provided: true } }

    it 'clears the flag while keeping the other existing metadata for blank inputs' do
      expect { upload_again }.to_not change(account.drive_files, :count)

      expect(existing.reload).to_not be_sensitive
      expect(existing).to have_attributes(description: 'Original description', folder_id: folder.id)
    end
  end
end
