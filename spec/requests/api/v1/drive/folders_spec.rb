# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive folders API' do
  include_context 'with API authentication', oauth_scopes: 'read write:media'

  before do
    Setting.drive_enabled = true
  end

  describe 'folder ownership' do
    let(:foreign_folder) { Fabricate(:account).drive_folders.create!(name: 'Foreign') }

    it 'does not show another account folder' do
      get "/api/v1/drive/folders/#{foreign_folder.id}", headers: headers

      expect(response).to have_http_status(404)
    end

    it 'does not update another account folder' do
      patch "/api/v1/drive/folders/#{foreign_folder.id}", headers: headers, params: { name: 'Changed' }

      expect(response).to have_http_status(404)
      expect(foreign_folder.reload.name).to eq('Foreign')
    end

    it 'does not destroy another account folder' do
      delete "/api/v1/drive/folders/#{foreign_folder.id}", headers: headers

      expect(response).to have_http_status(404)
      expect(DriveFolder).to exist(foreign_folder.id)
    end
  end
end
