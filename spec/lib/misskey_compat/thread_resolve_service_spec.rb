# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::ThreadResolveService do
  subject { described_class.new }

  let(:remote_account) { Fabricate(:account, domain: 'remote.example', uri: 'https://remote.example/users/alice', inbox_url: 'https://remote.example/users/alice/inbox') }
  let(:parent) { Fabricate(:status, account: remote_account, uri: 'https://remote.example/notes/parent') }
  let(:status) { Fabricate(:status, account: remote_account, uri: 'https://remote.example/notes/child', reply: true) }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: status.uri,
      type: 'Note',
      attributedTo: remote_account.uri,
      inReplyTo: parent.uri,
      content: 'reply',
    }
  end

  before do
    Rails.cache.delete("misskey_compat:thread_resolve:#{status.id}")
    stub_request(:get, status.uri).to_return(status: 200, body: json.to_json, headers: { 'Content-Type': 'application/activity+json' })
  end

  it 'links the reply to its parent fetched from the remote object' do
    expect(subject.call(status).thread).to eq parent
  end

  it 'does not trust a redirected response from another origin' do
    stub_request(:get, status.uri).to_return(status: 302, headers: { Location: 'https://evil.example/notes/child' })
    stub_request(:get, 'https://evil.example/notes/child').to_return(status: 200, body: json.to_json, headers: { 'Content-Type': 'application/activity+json' })

    expect(subject.call(status).thread).to be_nil
  end
end
