# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SystemCheck::VoiceRelayCheck do
  subject(:check) { described_class.new(user) }

  let(:user) { Fabricate(:admin_user) }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.voice_call_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.voice_call_enabled = false
  end

  it 'is skipped while voice calls are off or for users without the settings permission' do
    expect(check.skip?).to be false
    expect(described_class.new(Fabricate(:moderator_user)).skip?).to be true

    Setting.voice_call_enabled = false
    expect(check.skip?).to be true
  end

  it 'warns when no relay is usable and names revoked relays as critical' do
    expect(check.pass?).to be false
    expect(check.message).to have_attributes(key: :voice_relay_unavailable_check, critical: false, action: '/admin/voice_relay_providers')

    Fabricate(:voice_relay_provider, origin: 'https://ok.example.org').update_columns(validated: true)
    expect(described_class.new(user).pass?).to be true

    Fabricate(:voice_relay_provider, origin: 'https://gone.example.org').update_columns(revoked_at: Time.now.utc)
    Fabricate(:voice_relay_provider, origin: 'https://off.example.org', enabled: false).update_columns(revoked_at: Time.now.utc)
    revoked = described_class.new(user)
    expect(revoked.pass?).to be false
    expect(revoked.message).to have_attributes(key: :voice_relay_revoked_check, value: 'https://gone.example.org', critical: true)
  end
end
