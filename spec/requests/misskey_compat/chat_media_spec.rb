# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey chat media downloads' do
  let(:owner) { Fabricate(:user).account }
  let(:viewer) { Fabricate(:user).account }
  let(:conversation) do
    ChatConversation.create!(conversation_type: :group, title: 'Private room', owner_account: owner).tap do |room|
      room.memberships.create!(account: owner, role: :owner)
      room.memberships.create!(account: viewer)
    end
  end
  let(:message) { conversation.messages.create!(account: owner, text: 'image') }
  let(:media) { Fabricate(:media_attachment, account: owner) }

  before do
    Setting.chat_enabled = true
    Setting.misskey_compat_enabled = true
    Setting.chat_federation_enabled = false
    message.media_attachments << media
  end

  after do
    Setting.chat_enabled = false
    Setting.misskey_compat_enabled = false
  end

  def download_path
    URI.parse(MisskeyCompat::ChatSerializer.message(message, viewer: viewer).dig(:file, :url)).request_uri
  end

  it 'stops an issued attachment URL as soon as compatibility is turned off, and not one from the chat API, but takes it again if compatibility comes back before it expires' do
    misskey_path = download_path
    rest_path = URI.parse(REST::MediaAttachmentSerializer.new(media, current_account: viewer).as_json[:url]).request_uri

    Setting.misskey_compat_enabled = false

    get misskey_path
    expect(response).to have_http_status(404)

    get rest_path
    expect(response).to have_http_status(:redirect)

    Setting.misskey_compat_enabled = true
    get misskey_path
    expect(response).to have_http_status(:redirect)
  end

  it 'allows the authorized client to load its attachment without a Rails session, and revokes the URL when its viewer leaves the room' do
    path = download_path

    get path
    expect(response).to have_http_status(:redirect)

    conversation.memberships.find_by!(account: viewer).destroy!
    get path
    expect(response).to have_http_status(404)
  end

  it 'allows scoped downloads in limited federation mode while rejecting invalid capabilities' do
    allow(Rails.configuration.x.mastodon).to receive(:limited_federation_mode).and_return(true)

    get download_path
    expect(response).to redirect_to(%r{system/media_attachments})

    get "/media_proxy/#{media.id}/original", params: { chat_token: 'invalid' }
    expect(response).to have_http_status(404)
  end

  context 'when the capability no longer works' do
    it 'refuses session downloads while chat is disabled' do
      sign_in viewer.user
      path = download_path
      Setting.chat_enabled = false

      get path
      expect(response).to have_http_status(404)

      get "/media_proxy/#{media.id}/original"
      expect(response).to have_http_status(404)
    end

    it 'refuses session downloads while the viewer is suspended' do
      sign_in viewer.user
      path = download_path
      viewer.suspend!

      get path
      expect(response).to have_http_status(404)

      get "/media_proxy/#{media.id}/original"
      expect(response).to have_http_status(404)
    end

    it 'lets a signed-in member keep opening the attachment, also with a token given as a list, until they have left the room' do
      sign_in viewer.user
      path = download_path

      travel 11.minutes do
        get path
        expect(response).to redirect_to(%r{system/media_attachments})
      end

      get "/media_proxy/#{media.id}/original", params: { chat_token: 'invalid' }
      expect(response).to redirect_to(%r{system/media_attachments})

      get "/media_proxy/#{media.id}/original", params: { chat_token: ['forged'], token: ['forged'] }
      expect(response).to redirect_to(%r{system/media_attachments})

      conversation.memberships.find_by!(account: viewer).destroy!
      travel 11.minutes do
        get path
        expect(response).to have_http_status(404)
      end
    end

    it 'refuses a signed-in account that is not a member' do
      sign_in Fabricate(:user)

      get "/media_proxy/#{media.id}/original", params: { chat_token: 'invalid' }

      expect(response).to have_http_status(404)
    end

    it 'does not open public media to a signed-out visitor in limited federation mode' do
      allow(Rails.configuration.x.mastodon).to receive(:limited_federation_mode).and_return(true)
      public_media = Fabricate(:media_attachment, status: Fabricate(:status, visibility: :public))

      get "/media_proxy/#{public_media.id}/original", params: { chat_token: 'invalid' }

      expect(response).to have_http_status(404)
    end
  end

  it 'treats a token given as a list or a hash as invalid instead of failing' do
    [{ chat_token: ['forged'] }, { chat_token: { 'a' => 'b' } }, { token: ['forged'] }, { token: { 'a' => 'b' } }].each do |params|
      get "/media_proxy/#{media.id}/original", params: params

      expect(response).to have_http_status(404), params.inspect
    end
  end

  it 'does not allow a previously issued URL to reveal a deleted message attachment' do
    path = download_path
    message.update!(deleted_at: Time.current)

    get path

    expect(response).to have_http_status(404)
  end

  it 'expires the download capability and denies unsigned requests' do
    path = download_path
    travel 11.minutes do
      get path
      expect(response).to have_http_status(404)
    end

    get "/media_proxy/#{media.id}/original"
    expect(response).to have_http_status(404)
  end
end
