# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::LinkPreviewDirectHosts do
  it 'matches listed domains and their subdomains only, and rejects addresses and malformed entries' do
    value = "YouTube.com, *.google.com\nyoutu.be."

    expect(described_class.hosts(value)).to eq %w(youtube.com google.com youtu.be)
    expect(described_class.allowed?('https://m.youtube.com/watch', value)).to be true
    expect(described_class.allowed?('http://google.com/', value)).to be true
    expect(described_class.allowed?('https://notyoutube.com/', value)).to be false
    expect(described_class.allowed?('https://user@youtube.com/', value)).to be false
    expect(described_class.allowed?('ftp://youtube.com/', value)).to be false
    expect(described_class.invalid_entries('youtube.com 203.0.113.1 https://x.example example.onion localhost [::1]')).to eq %w(203.0.113.1 https://x.example example.onion localhost [::1])

    form = Form::AdminSettings.new(link_preview_direct_hosts: "youtube.com\n203.0.113.1")
    expect(form).to_not be_valid
    expect(form.errors[:link_preview_direct_hosts].join).to include('203.0.113.1')
  end
end
