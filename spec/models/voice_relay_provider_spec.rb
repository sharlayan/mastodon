# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VoiceRelayProvider do
  let(:secret) { 'r' * 40 }
  let(:capacity_url) { 'https://voice.example.org/voice-relay/v1/capacity' }
  let(:capacity) { { protocolVersion: 1, enabled: true, accepting: true, maxSlots: 10, reservedSlots: 0, remainingSlots: 10, remainingRooms: 1 } }

  it 'normalizes the origin, encrypts the secret and keeps it when the edit leaves it blank' do
    provider = described_class.create!(origin: 'https://Voice.Example.org/', secret:)

    expect(provider.origin).to eq 'https://voice.example.org'
    expect(provider.secret_ciphertext).to start_with('v1:')
    expect(provider.secret_ciphertext).to_not include(secret)
    expect(described_class.find(provider.id).secret).to eq secret

    version = provider.credential_version
    provider.update!(secret: '', enabled: false)
    expect(provider.reload.secret).to eq secret
    expect(provider.credential_version).to eq version
  end

  it 'rejects invalid origins, the own origin, short secrets and more than the provider limit' do
    expect(described_class.new(origin: 'http://voice.example.org', secret:)).to_not be_valid
    own = described_class.new(origin: 'https://cb6e6126.ngrok.io', secret:)
    expect(own).to_not be_valid
    expect(own.errors.details[:origin]).to include(error: :own_origin)

    short = described_class.new(origin: 'https://voice.example.org', secret: 'short')
    expect(short).to_not be_valid
    expect(short.errors.details[:secret]).to include(error: :too_short, count: 32)
    expect(described_class.new(origin: 'https://voice.example.org')).to_not be_valid

    Fabricate.times(described_class::MAX_PROVIDERS, :voice_relay_provider)
    over = described_class.new(origin: 'https://voice.example.org', secret:)
    expect(over).to_not be_valid
    expect(over.errors.details[:base]).to include(error: :provider_limit, count: described_class::MAX_PROVIDERS)
  end

  it 'records approval from the capacity check and only revokes it on authentication failures' do
    provider = described_class.create!(origin: 'https://voice.example.org', secret:)

    stub_request(:get, capacity_url).to_return(status: 200, body: capacity.to_json)
    provider.check!
    expect(provider.reload).to have_attributes(validated: true, last_error: nil, capacity: include('maxSlots' => 10))
    expect(provider.last_checked_at).to be_present

    stub_request(:get, capacity_url).to_return(status: 503, body: { code: 'PROVIDER_UNAVAILABLE' }.to_json)
    expect { provider.check! }.to raise_error(Sharlayan::VoiceRelay::Error)
    expect(provider.reload).to have_attributes(validated: true, last_error: 'PROVIDER_UNAVAILABLE')

    stub_request(:get, capacity_url).to_return(status: 401, body: { code: 'UNAUTHORIZED' }.to_json)
    expect { provider.check! }.to raise_error(Sharlayan::VoiceRelay::Error)
    expect(provider.reload).to have_attributes(validated: false, last_error: 'UNAUTHORIZED')

    stub_request(:get, capacity_url).to_return(status: 200, body: capacity.to_json)
    provider.check!
    provider.update!(secret: 'n' * 40)
    expect(provider.reload).to have_attributes(validated: false, capacity: {})
  end
end
