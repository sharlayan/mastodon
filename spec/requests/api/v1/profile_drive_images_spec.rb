# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Profile images from Drive' do
  include_context 'with API authentication', oauth_scopes: 'write:accounts'

  let(:account) { user.account }
  let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }

  before do
    Setting.drive_enabled = true
  end

  %w(/api/v1/profile /api/v1/accounts/update_credentials).each do |endpoint|
    describe "PATCH #{endpoint}" do
      subject(:update_profile) { patch endpoint, headers: headers, params: params, as: :json }

      let(:params) { { avatar_drive_file_id: drive_file.id.to_s, header_drive_file_id: drive_file.id.to_s } }

      it_behaves_like 'forbidden for wrong scope', 'read:accounts write:media'

      it 'processes independent profile copies that survive Drive deletion', :attachment_processing do
        source_path = drive_file.file.path
        source_bytes = File.binread(source_path)

        expect { update_profile }.to not_change(DriveFile, :count).and not_change(MediaAttachment, :count)

        expect(response).to have_http_status(200)
        account.reload
        expect([account.avatar.path, account.header.path]).to_not include(source_path)
        expect(File.binread(source_path)).to eq(source_bytes)
        expect(FastImage.size(account.avatar.path)).to eq(Account::Avatar::AVATAR_DIMENSIONS)
        expect(drive_file.reload).to_not be_attached
        expect(ActivityPub::UpdateDistributionWorker).to have_enqueued_sidekiq_job(account.id)

        avatar_bytes = File.binread(account.avatar.path)
        header_bytes = File.binread(account.header.path)
        drive_file.destroy!

        expect(File).to_not exist(source_path)
        expect(File.binread(account.reload.avatar.path)).to eq(avatar_bytes)
        expect(File.binread(account.header.path)).to eq(header_bytes)
      end

      it 'preserves the Drive original when the profile copies are removed' do
        update_profile
        expect(response).to have_http_status(200)

        account.reload.update!(avatar: nil, header: nil)

        expect(drive_file.reload.file).to exist
      end

      it 'updates descriptions alongside the selected files' do
        params.merge!(avatar_description: 'Portrait', header_description: 'Landscape')

        update_profile

        expect(response).to have_http_status(200)
        expect(account.reload).to have_attributes(avatar_description: 'Portrait', header_description: 'Landscape')
      end

      it 'does not save any profile changes if one selected file is missing' do
        params.merge!(header_drive_file_id: '0', display_name: 'Changed')

        expect { update_profile }.to not_change { account.reload.display_name }
          .and not_change { account.reload.avatar_file_name }
          .and(not_change { account.reload.header_file_name })

        expect(response).to have_http_status(404)
      end

      context 'with another account’s file' do
        let(:drive_file) { Fabricate(:account).drive_files.create!(file: attachment_fixture('attachment.jpg')) }

        it 'rejects the selection' do
          update_profile

          expect(response).to have_http_status(404)
          expect(account.reload.avatar).to_not exist
          expect(account.header).to_not exist
        end
      end

      context 'with a non-image file' do
        let(:drive_file) { account.drive_files.create!(file: attachment_fixture('bookmark-imports.txt')) }

        before do
          Setting.drive_allowed_extensions = 'txt'
        end

        it 'returns a validation error without changing the profile' do
          update_profile

          expect(response).to have_http_status(422)
          expect(response.parsed_body[:details]).to include(avatar: contain_exactly(include(error: 'ERR_INVALID')))
          expect(account.reload.avatar).to_not exist
          expect(account.header).to_not exist
        end
      end

      context 'with a file exceeding the profile image limit' do
        before do
          File.truncate(drive_file.file.path, Account::Avatar::AVATAR_LIMIT + 1)
        end

        it 'applies the usual profile image size validation' do
          update_profile

          expect(response).to have_http_status(422)
          expect(account.reload.avatar).to_not exist
          expect(account.header).to_not exist
        end
      end

      context 'when the stored original is unavailable' do
        before do
          File.unlink(drive_file.file.path)
        end

        it 'returns a validation error without changing the profile' do
          params[:display_name] = 'Changed'

          expect { update_profile }.to not_change { account.reload.display_name }
            .and not_change { account.reload.avatar_file_name }
            .and(not_change { account.reload.header_file_name })

          expect(response).to have_http_status(422)
          expect(response.parsed_body[:details]).to include(avatar: contain_exactly(include(error: 'ERR_INVALID')))
          expect(ActivityPub::UpdateDistributionWorker).to_not have_enqueued_sidekiq_job(account.id)
        end
      end

      context 'with an empty stored original' do
        before do
          File.truncate(drive_file.file.path, 0)
        end

        it 'rejects the empty copy before changing the profile' do
          update_profile

          expect(response).to have_http_status(422)
          expect(response.parsed_body[:details]).to include(avatar: contain_exactly(include(error: 'ERR_INVALID')))
          expect(account.reload.avatar).to_not exist
          expect(account.header).to_not exist
        end
      end

      context 'when image dimension validation fails', :attachment_processing do
        before do
          drive_file
          allow(FastImage).to receive(:size).and_return([10_000, 10_000])
        end

        it 'returns a validation error instead of reporting a successful update' do
          update_profile

          expect(response).to have_http_status(422)
          expect(account.reload.avatar).to_not exist
          expect(account.header).to_not exist
          expect(ActivityPub::UpdateDistributionWorker).to_not have_enqueued_sidekiq_job(account.id)
        end

        context 'when only a header is selected' do
          let(:params) { { header_drive_file_id: drive_file.id.to_s } }

          it 'identifies the header as the invalid image' do
            update_profile

            expect(response).to have_http_status(422)
            expect(response.parsed_body[:details]).to include(header: contain_exactly(include(error: 'ERR_INVALID')))
            expect(response.parsed_body[:details]).to_not have_key(:avatar)
          end
        end
      end

      context 'when Drive is disabled' do
        before do
          Setting.drive_enabled = false
        end

        it 'rejects Drive selections' do
          update_profile

          expect(response).to have_http_status(404)
        end

        it 'allows ordinary profile edits' do
          patch endpoint, headers: headers, params: { display_name: 'Updated' }, as: :json

          expect(response).to have_http_status(200)
          expect(account.reload.display_name).to eq('Updated')
        end
      end
    end
  end
end
