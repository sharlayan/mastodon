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

  it 'allows the authorized client to load its attachment without a Rails session' do
    get download_path

    expect(response).to have_http_status(:redirect)
  end

  it 'revokes an issued attachment URL when its viewer leaves the room' do
    path = download_path
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
