# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceRelay::Client do
  subject(:client) { described_class.new(provider) }

  let(:secret) { 's' * 40 }
  let(:provider) { Fabricate(:voice_relay_provider, origin: 'https://voice.example.org', secret:) }
  let(:capacity_url) { 'https://voice.example.org/voice-relay/v1/capacity' }
  let(:capacity) do
    {
      protocolVersion: 1, enabled: true, accepting: true, maxSlots: 100, reservedSlots: 10, remainingSlots: 90, remainingRooms: 2,
      allowScreenShare: true, mediaProvider: 'https://voice.example.org',
      screenShareLimits: { maxWidth: 1920, maxHeight: 1080, maxFrameRate: 30, maxBitrate: 3_000_000 },
      capabilities: { cancelPending: true, includeIceServers: true }
    }
  end

  def json_response(body, status: 200)
    { status:, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  it 'signs requests with a short-lived relay client JWT and returns the validated capacity' do
    stub_request(:get, capacity_url).to_return(json_response(capacity.merge(unknown: 'ignored')))

    expect(client.capacity).to include(
      'enabled' => true, 'maxSlots' => 100, 'remainingRooms' => 2, 'allowScreenShare' => true,
      'screenShareLimits' => { 'maxWidth' => 1920, 'maxHeight' => 1080, 'maxFrameRate' => 30, 'maxBitrate' => 3_000_000 },
      'capabilities' => { 'cancelPending' => true, 'includeIceServers' => true }
    )

    expect(a_request(:get, capacity_url).with do |request|
      token = request.headers['Authorization'].delete_prefix('Bearer ')
      payload, header = JWT.decode(token, secret, true, algorithm: 'HS256', aud: 'https://voice.example.org', verify_aud: true, iss: 'https://cb6e6126.ngrok.io', verify_iss: true)

      header == { 'alg' => 'HS256', 'typ' => 'voice-relay-client+jwt' } &&
        payload.keys.sort == %w(aud exp iat iss) &&
        payload['exp'] - payload['iat'] == 60
    end).to have_been_made
  end

  it 'keeps relay error codes and does not follow redirects' do
    stub_request(:get, capacity_url).to_return(json_response({ code: 'CLIENT_DISABLED' }, status: 403))
    expect { client.capacity }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect([error.code, error.status, error.revoked?]).to eq ['CLIENT_DISABLED', 403, true] }

    stub_request(:get, capacity_url).to_return(status: 302, headers: { 'Location' => 'https://elsewhere.example/voice-relay/v1/capacity' })
    expect { client.capacity }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect([error.code, error.status]).to eq ['PROVIDER_UNAVAILABLE', 302] }
    expect(a_request(:get, 'https://elsewhere.example/voice-relay/v1/capacity')).to_not have_been_made
  end

  it 'rejects malformed or unreachable responses' do
    stub_request(:get, capacity_url).to_return(json_response(capacity.merge(protocolVersion: 2)))
    expect { client.capacity }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'INVALID_RESPONSE' }

    stub_request(:get, capacity_url).to_return(json_response(capacity.merge(screenShareLimits: { maxWidth: 0, maxHeight: 1, maxFrameRate: 1, maxBitrate: 1 })))
    expect { client.capacity }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'INVALID_RESPONSE' }

    stub_request(:get, capacity_url).to_raise(HTTP::ConnectionError)
    expect { client.capacity }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect([error.code, error.status]).to eq ['PROVIDER_UNAVAILABLE', 503] }
  end

  it 'sends JSON bodies for write requests' do
    stub = stub_request(:post, 'https://voice.example.org/voice-relay/v1/allocations')
      .with(body: { roomKey: 'k', generation: 'g', slots: 2 }.to_json, headers: { 'Content-Type' => 'application/json' })
      .to_return(json_response({ id: 'a1' }))

    expect(client.request(:post, '/allocations', { roomKey: 'k', generation: 'g', slots: 2 })).to eq('id' => 'a1')
    expect(stub).to have_been_requested
  end
end
