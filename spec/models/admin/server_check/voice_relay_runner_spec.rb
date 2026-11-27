# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::ServerCheck::VoiceRelayRunner do
  subject(:runner) { described_class.new }

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

  it 'is registered as a synchronous server check' do
    expect(Admin::ServerCheck::RUNNERS).to include(described_class)
    expect(described_class.key).to eq 'voice_relay'
    expect(runner).to be_sync
  end

  it 'is limited to users with the settings permission while voice calls are on' do
    expect(runner.authorized?(user)).to be true
    expect(runner.authorized?(Fabricate(:moderator_user))).to be false

    Setting.voice_call_enabled = false
    expect(runner.authorized?(user)).to be false
  end

  it 'warns when no relay is usable and names revoked relays as critical' do
    expect(runner.run).to have_attributes(status: :pending, severity: :warning, data: { reason: :unavailable })

    Fabricate(:voice_relay_provider, origin: 'https://ok.example.org').update_columns(validated: true)
    expect(described_class.new.run).to be_ok

    Fabricate(:voice_relay_provider, origin: 'https://gone.example.org').update_columns(revoked_at: Time.now.utc)
    Fabricate(:voice_relay_provider, origin: 'https://off.example.org', enabled: false).update_columns(revoked_at: Time.now.utc)
    expect(described_class.new.run).to have_attributes(status: :pending, severity: :critical, data: { reason: :revoked, providers_str: 'https://gone.example.org' })
  end

  it 'renders a title, lead and setup link for every reported state' do
    helper = Class.new(ActionView::Base) do
      include Rails.application.routes.url_helpers
      include Admin::ServerChecksHelper

      def default_url_options
        { host: 'test.host' }
      end
    end.empty
    check = Admin::ServerCheck.new(key: 'voice_relay')

    check.run
    expect(helper.admin_server_check_title(check)).to be_present
    expect(helper.admin_server_check_lead(check)).to be_present
    expect(helper.admin_server_check_setup_url(check)).to end_with '/admin/voice_relay_providers'

    Fabricate(:voice_relay_provider, origin: 'https://gone.example.org').update_columns(revoked_at: Time.now.utc)
    revoked = Admin::ServerCheck.new(key: 'voice_relay')
    revoked.run
    expect(helper.admin_server_check_lead(revoked)).to include('https://gone.example.org')
  end
end
