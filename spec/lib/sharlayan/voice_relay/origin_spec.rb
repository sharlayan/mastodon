# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceRelay::Origin do
  it 'normalizes public HTTPS origins and rejects everything else' do
    expect(described_class.normalize(' https://Voice.Example.org/ ')).to eq 'https://voice.example.org'
    expect(described_class.normalize('https://voice.example.org:443')).to eq 'https://voice.example.org'
    expect(described_class.normalize('https://voice.example.org:8443')).to eq 'https://voice.example.org:8443'

    [
      nil, '', 'voice.example.org', 'http://voice.example.org', 'https://user:pass@voice.example.org',
      'https://voice.example.org/relay', 'https://voice.example.org/?a=1', 'https://voice.example.org/#x',
      'https://127.0.0.1', 'https://[::1]', 'https://localhost', 'https://relay.localhost', 'https://exa mple.org'
    ].each do |value|
      expect { described_class.normalize(value) }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'INVALID_PROVIDER' }
    end
  end

  it 'derives the local origin from the web domain' do
    expect(described_class.local).to eq 'https://cb6e6126.ngrok.io'
    expect(described_class.local?('https://cb6e6126.ngrok.io')).to be true
  end
end
