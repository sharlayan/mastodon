# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceRelay::IceServers do
  def server(*urls, **credentials)
    { 'urls' => urls }.merge(credentials.stringify_keys)
  end

  it 'keeps public STUN and TURN servers with their credentials' do
    servers = [
      server('turn:turn.example.org:3478?transport=udp', 'turns:[2606:4700::1]:443', username: 'u', credential: 'c'),
      server('stun:stun.example.org', 'stun:8.8.8.8:3478', 'stun:[64:ff9b::808:808]'),
    ]

    expect(described_class.parse(servers)).to eq [
      { urls: ['turn:turn.example.org:3478?transport=udp', 'turns:[2606:4700::1]:443'], username: 'u', credential: 'c' },
      { urls: ['stun:stun.example.org', 'stun:8.8.8.8:3478', 'stun:[64:ff9b::808:808]'] },
    ]
  end

  it 'refuses the whole list when a server points into the local network or browsers would refuse it' do
    urls = %w(
      stun:127.0.0.1 stun:10.0.0.1:3478 stun:172.16.0.1 stun:192.168.1.1 stun:100.64.0.1 stun:169.254.1.1 stun:0.0.0.0
      stun:224.0.0.1 stun:255.255.255.255 stun:198.18.0.1 stun:[::1] stun:[::] stun:[fe80::1] stun:[fc00::1] stun:[fec0::1]
      stun:[ff02::1] stun:[::ffff:127.0.0.1] stun:[::ffff:0:a00:1] stun:[64:ff9b::a00:1] stun:[64:ff9b:1::a00:1]
      stun:[2002:c0a8:101::] stun:[2001:2::1] stun:2130706433 stun:0x7f000001 stun:127.1 stun:0177.0.0.1 stun:1.2.3.4.
      stun:router stun:localhost stun:nas.local stun:printer.home.arpa stun:db.internal stun:localhost.localdomain
      stun:stun.example.org:53 stun:stun.example.org:99999 stun:stun.example.org: stun:[::1 stun:[2606:4700::1]x
      STUN:stun.example.org stuns:stun.example.org stun:stün.example.org stun:
    )

    urls.each { |url| expect(described_class.parse([server(url)])).to(be_nil, url) }
    expect(described_class.parse([server('stun:stun.example.org'), server('stun:10.0.0.1')])).to be_nil
  end

  it 'refuses TURN servers without credentials, malformed credentials and oversized lists' do
    expect(described_class.parse([server('turn:turn.example.org')])).to be_nil
    expect(described_class.parse([server('turn:turn.example.org', username: '', credential: 'c')])).to be_nil
    expect(described_class.parse([server('stun:stun.example.org', username: nil)])).to be_nil
    expect(described_class.parse([server('turn:turn.example.org', username: 'u', credential: 'c' * 513)])).to be_nil
    expect(described_class.parse([])).to be_nil
    expect(described_class.parse(Array.new(5) { server('stun:stun.example.org') })).to be_nil
    expect(described_class.parse([server(*Array.new(9) { |index| "stun:stun#{index}.example.org" })])).to be_nil
    expect(described_class.parse(Array.new(4) { server(*Array.new(8) { |index| "stun:stun#{index}.example.org" }) })).to be_present
  end
end
