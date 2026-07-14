# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Media' do
  describe 'GET /media/:id' do
    context 'when the media attachment is a Drive pointer' do
      let(:account) { Fabricate(:account) }
      let(:status) { Fabricate(:status, account: account) }
      let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
      let(:media_attachment) do
        drive_file.build_pointer(account).tap do |pointer|
          pointer.status = status
          pointer.save!
        end
      end

      it 'redirects to the Drive resolver' do
        get medium_path(id: media_attachment.id)

        expect(response).to redirect_to(%r{/drive_media/#{media_attachment.drive_access_key}/original\z})
      end
    end

    context 'when the media attachment does not exist' do
      it 'responds with not found' do
        get '/media/missing'

        expect(response)
          .to have_http_status(404)
      end
    end

    context 'when the media attachment has a shortcode' do
      let(:media_attachment) { Fabricate :media_attachment, status: status, shortcode: 'OI6IgDzG-nYTqvDQ994' }

      context 'when attached to a status' do
        let(:status) { Fabricate :status }

        it 'redirects to file url' do
          get medium_path(id: media_attachment.shortcode)

          expect(response)
            .to redirect_to(media_attachment.file.url(:original))
        end
      end

      context 'when not attached to a status' do
        let(:status) { nil }

        it 'responds with not found' do
          get medium_path(id: media_attachment.shortcode)

          expect(response)
            .to have_http_status(404)
        end
      end

      context 'when attached to non-public status' do
        let(:status) { Fabricate :status, visibility: :direct }

        it 'responds with not found' do
          get medium_path(id: media_attachment.shortcode)

          expect(response)
            .to have_http_status(404)
        end
      end
    end

    context 'when the media attachment does not have a shortcode' do
      let(:media_attachment) { Fabricate :media_attachment, status: status, shortcode: nil }

      context 'when attached to a status' do
        let(:status) { Fabricate :status }

        it 'redirects to file url' do
          get medium_path(id: media_attachment.id)

          expect(response)
            .to redirect_to(media_attachment.file.url(:original))
        end
      end

      context 'when not attached to a status' do
        let(:status) { nil }

        it 'responds with not found' do
          get medium_path(id: media_attachment.id)

          expect(response)
            .to have_http_status(404)
        end
      end

      context 'when attached to non-public status' do
        let(:status) { Fabricate :status, visibility: :direct }

        it 'responds with not found' do
          get medium_path(id: media_attachment.id)

          expect(response)
            .to have_http_status(404)
        end
      end
    end
  end

  describe 'GET /media/:medium_id/player' do
    context 'when the media attachment is a Drive pointer' do
      let(:account) { Fabricate(:account) }
      let(:status) { Fabricate(:status, account: account) }
      let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
      let(:media) do
        drive_file.build_pointer(account).tap do |pointer|
          pointer.type = :video
          pointer.status = status
          pointer.save!
        end
      end

      it 'renders the player with Drive resolver URLs' do
        get player_medium_path(media)

        expect(response).to have_http_status(200)
        expect(response.body).to include("/drive_media/#{media.drive_access_key}/original", "/drive_media/#{media.drive_access_key}/small")
      end
    end

    context 'when media type is not large format type' do
      let(:media) { Fabricate :media_attachment }

      it 'responds with not found' do
        get player_medium_path(media)

        expect(response)
          .to have_http_status(404)
      end
    end
  end
end
