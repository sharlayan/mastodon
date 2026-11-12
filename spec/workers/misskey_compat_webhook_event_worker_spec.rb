# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompatWebhookEventWorker do
  let(:worker)  { described_class.new }
  let(:account) { Fabricate(:user).account }
  let(:author)  { Fabricate(:account) }
  let!(:webhook) { MisskeyWebhook.create!(account: account, name: 'All', url: 'https://hooks.example/all', events: %w(reply follow followed)) }

  def queued_payloads
    MisskeyCompatWebhookDeliveryWorker.jobs.map { |job| JSON.parse(job['args'][1]) }
  end

  it 'queues a Misskey payload with the serialized note for visible replies only' do
    parent = Fabricate(:status, account: account)
    reply = Fabricate(:status, account: author, thread: parent)
    hidden = Fabricate(:status, account: author, thread: parent, visibility: :direct)

    worker.perform('reply', account.id.to_s, 'Status', reply.id.to_s)
    worker.perform('reply', account.id.to_s, 'Status', hidden.id.to_s)
    worker.perform('note', account.id.to_s, 'Status', reply.id.to_s)

    expect(queued_payloads).to contain_exactly(include(
                                                 'hookId' => MisskeyCompat::MiId.encode(webhook.id),
                                                 'userId' => MisskeyCompat::MiId.encode(account.id),
                                                 'type' => 'reply',
                                                 'server' => "https://#{Rails.configuration.x.web_domain}",
                                                 'eventId' => be_present,
                                                 'body' => { 'note' => include('id' => MisskeyCompat::MiId.encode(reply.id), 'replyId' => MisskeyCompat::MiId.encode(parent.id)) }
                                               ))
  end

  it 'serializes the other user and skips muted threads and unavailable owners' do
    worker.perform('follow', account.id.to_s, 'Account', author.id.to_s)
    worker.perform('followed', account.id.to_s, 'Account', author.id.to_s)

    expect(queued_payloads.map { |payload| [payload['type'], payload.dig('body', 'user', 'id'), payload.dig('body', 'user').key?('isFollowing')] })
      .to eq([['follow', MisskeyCompat::MiId.encode(author.id), true], ['followed', MisskeyCompat::MiId.encode(author.id), false]])

    MisskeyCompatWebhookDeliveryWorker.clear
    parent = Fabricate(:status, account: account)
    reply = Fabricate(:status, account: author, thread: parent)
    account.mute_conversation!(parent.conversation)
    worker.perform('reply', account.id.to_s, 'Status', reply.id.to_s)
    account.user.disable!
    worker.perform('follow', account.id.to_s, 'Account', author.id.to_s)

    expect(MisskeyCompatWebhookDeliveryWorker.jobs).to be_empty
  end
end
