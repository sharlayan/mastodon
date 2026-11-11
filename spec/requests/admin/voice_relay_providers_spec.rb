# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin voice relay providers' do
  let(:admin) { Fabricate(:admin_user) }
  let(:secret) { 'a' * 40 }
  let(:capacity_url) { 'https://voice.example.org/voice-relay/v1/capacity' }
  let(:capacity) { { protocolVersion: 1, enabled: true, accepting: true, maxSlots: 50, reservedSlots: 5, remainingSlots: 45, remainingRooms: 2, allowScreenShare: true } }

  before { sign_in admin }

  it 'registers a relay without echoing the secret and records it in the audit log' do
    get admin_voice_relay_providers_path
    expect(response).to have_http_status(200)
    expect(response.body).to include('https://cb6e6126.ngrok.io')

    post admin_voice_relay_providers_path, params: { voice_relay_provider: { origin: 'https://voice.example.org/', secret: } }
    expect(response).to redirect_to(admin_voice_relay_providers_path)
    provider = VoiceRelayProvider.last
    expect(provider).to have_attributes(origin: 'https://voice.example.org', validated: false)
    expect(Admin::ActionLog.last).to have_attributes(action: :create, target: provider, human_identifier: 'https://voice.example.org')

    get edit_admin_voice_relay_provider_path(provider)
    expect(response).to have_http_status(200)
    expect(response.body).to_not include(secret, provider.secret_ciphertext)
  end

  it 'checks approval, then disables and deletes the relay with audit log entries' do
    provider = Fabricate(:voice_relay_provider, origin: 'https://voice.example.org')

    stub_request(:get, capacity_url).to_return(status: 200, body: capacity.to_json)
    post check_admin_voice_relay_provider_path(provider)
    expect(provider.reload.validated).to be true
    get admin_voice_relay_providers_path
    expect(response.body).to include(I18n.t('admin.voice_relay_providers.slots', reserved: 5, max: 50, rooms: 2))

    stub_request(:get, capacity_url).to_return(status: 403, body: { code: 'CLIENT_DISABLED' }.to_json)
    post check_admin_voice_relay_provider_path(provider)
    expect(flash[:alert]).to include('CLIENT_DISABLED')
    expect(provider.reload.validated).to be false

    post disable_admin_voice_relay_provider_path(provider)
    delete admin_voice_relay_provider_path(provider)
    expect(VoiceRelayProvider).to_not exist(provider.id)
    expect(Admin::ActionLog.where(target_type: 'VoiceRelayProvider').pluck(:action)).to eq %w(disable destroy)
  end

  it 'rerenders the form for invalid input and denies users without the settings permission' do
    post admin_voice_relay_providers_path, params: { voice_relay_provider: { origin: 'http://voice.example.org', secret: 'short' } }
    expect(response).to have_http_status(200)
    expect(VoiceRelayProvider.count).to eq 0

    sign_in Fabricate(:moderator_user)
    get admin_voice_relay_providers_path
    expect(response).to have_http_status(403)
  end
end
