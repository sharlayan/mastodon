# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive settings API' do
  include_context 'with API authentication', oauth_scopes: 'read write:accounts'

  before do
    Setting.drive_enabled = true
  end

  describe 'GET /api/v1/drive/settings' do
    it 'returns the account Drive settings' do
      folder = user.account.drive_folders.create!(name: 'Uploads')
      user.update!(settings_attributes: {
        drive_keep_original_filename: false,
        drive_default_folder_id: folder.id.to_s,
      })

      get '/api/v1/drive/settings', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq(
        'keep_original_filename' => false,
        'default_folder_id' => folder.id.to_s,
        'upload_original_image' => true
      )
    end

    it 'does not expose a deleted default folder' do
      user.update!(settings_attributes: { drive_default_folder_id: '1234' })

      get '/api/v1/drive/settings', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:default_folder_id]).to be_nil
    end
  end

  describe 'PUT /api/v1/drive/settings' do
    it 'updates the settings and allows the Drive root as the default folder' do
      user.update!(settings_attributes: { drive_default_folder_id: '1234' })

      put '/api/v1/drive/settings', headers: headers, params: {
        keep_original_filename: false,
        default_folder_id: nil,
        upload_original_image: false,
      }

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq(
        'keep_original_filename' => false,
        'default_folder_id' => nil,
        'upload_original_image' => false
      )
      expect(user.reload.settings[:drive_default_folder_id]).to be_nil
      expect(user.reload.settings[:drive_upload_original_image]).to be(false)
    end

    it 'only accepts a default folder owned by the current account' do
      other_user = Fabricate(:user)
      folder = other_user.account.drive_folders.create!(name: 'Private')

      put '/api/v1/drive/settings', headers: headers, params: {
        keep_original_filename: true,
        default_folder_id: folder.id,
      }

      expect(response).to have_http_status(404)
      expect(user.reload.settings[:drive_default_folder_id]).to be_nil
    end
  end
end
