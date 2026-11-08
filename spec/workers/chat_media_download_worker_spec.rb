# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatMediaDownloadWorker, :attachment_processing do
  include_context 'with an open chat policy'

  let(:worker) { described_class.new }
  let(:service) { Sharlayan::ChatService.new }
  let(:local) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:urls) { Array.new(4) { |index| "https://remote.test/files/#{index}" } }
  let(:message) do
    service.receive_direct_message(
      local, remote,
      uri: 'https://remote.test/chat/messages/1',
      text: 'Pictures',
      attachments: urls.map { |url| { 'type' => 'Document', 'url' => url, 'mediaType' => 'image/jpeg' } }
    )
  end
  let(:published) { [] }

  # What an open screen has received, in order, for this message.
  def redraws
    published.select { |event| event['event'] == 'chat.message_update' }.map { |event| JSON.parse(event['payload']) }
  end

  def types_in(redraw)
    redraw['media_attachments'].pluck('type')
  end

  def serve(url, status: 200)
    return stub_request(:get, url).to_return(status: status) unless status == 200

    stub_request(:get, url).to_return(status: 200, body: attachment_fixture('attachment.jpg'), headers: { 'Content-Type' => 'image/jpeg' })
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_max_attachments = 4
    service.create_conversation(local, type: :direct, account_ids: [remote.id])
    message
    allow(service.redis).to receive(:publish) { |_channel, data| published << JSON.parse(data) }
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'starts with attachments that cannot be shown yet' do
    expect(message.media_attachments.reload.map(&:type)).to all(eq('unknown'))
    expect(message.media_attachments.map(&:needs_redownload?)).to all(be(true))
  end

  it 'redraws the message as each attachment arrives, until all of them show' do
    urls.each { |url| serve(url) }

    worker.perform(message.id)

    expect(redraws.size).to eq(4)
    expect(redraws.map { |redraw| types_in(redraw).count('image') }).to eq([1, 2, 3, 4])
    expect(redraws.pluck('id')).to all(eq(message.id.to_s))
  end

  it 'keeps the order of the attachments in every redraw' do
    urls.each { |url| serve(url) }

    worker.perform(message.id)

    expected = message.chat_message_media_attachments.order(:id).pluck(:media_attachment_id).map(&:to_s)
    expect(redraws.map { |redraw| redraw['media_attachments'].pluck('id') }).to all(eq(expected))
  end

  it 'does not mark the message as edited or keep an earlier version' do
    urls.each { |url| serve(url) }

    expect { worker.perform(message.id) }.to_not(change { message.reload.edited_at })

    expect(redraws.pluck('edited_at')).to all(be_nil)
    expect(message.edits).to be_empty
  end

  it 'shows the others when one fails for now, and tries only that one again' do
    urls.each { |url| serve(url) }
    failing = serve(urls[1], status: 503)

    expect { worker.perform(message.id) }.to raise_error(Mastodon::UnexpectedResponseError)

    expect(types_in(redraws.last)).to eq(%w(image unknown image image))

    remove_request_stub(failing)
    published.clear
    WebMock.reset_executed_requests!
    serve(urls[1])

    worker.perform(message.id)

    expect(types_in(redraws.last)).to eq(%w(image image image image))
    expect(redraws.size).to eq(1)
    expect(a_request(:get, urls[0])).to_not have_been_made
    expect(a_request(:get, urls[1])).to have_been_made.once
  end

  it 'does not try again when the other server says the file is gone, and still shows the rest' do
    urls.each { |url| serve(url) }
    serve(urls[2], status: 404)

    expect { worker.perform(message.id) }.to_not raise_error

    expect(types_in(redraws.last)).to eq(%w(image image unknown image))
  end

  it 'redraws once when a viewer already caused every file to be fetched' do
    message.media_attachments.each { |media| media.update!(file: attachment_fixture('attachment.jpg')) }

    worker.perform(message.id)

    expect(redraws.size).to eq(1)
    expect(types_in(redraws.first)).to all(eq('image'))
    expect(a_request(:get, urls[0])).to_not have_been_made
  end

  it 'neither fetches nor redraws a message that was deleted' do
    urls.each { |url| serve(url) }
    service.delete_remote_message(remote, message)
    published.clear

    worker.perform(message.id)

    expect(redraws).to be_empty
    expect(a_request(:get, urls[0])).to_not have_been_made
  end

  it 'stops as soon as the message is deleted while its attachments are being fetched' do
    serve(urls[0])
    stub_request(:get, urls[0]).to_return do
      ChatMessage.find(message.id).update!(deleted_at: Time.current)
      { status: 200, body: attachment_fixture('attachment.jpg'), headers: { 'Content-Type' => 'image/jpeg' } }
    end
    urls.drop(1).each { |url| serve(url) }

    worker.perform(message.id)

    expect(redraws).to be_empty
    expect(a_request(:get, urls[1])).to_not have_been_made
  end

  it 'neither fetches nor redraws a message whose author was suspended' do
    urls.each { |url| serve(url) }
    remote.suspend!

    worker.perform(message.id)

    expect(redraws).to be_empty
    expect(a_request(:get, urls[0])).to_not have_been_made
  end

  it 'does nothing for a message that no longer exists' do
    id = message.id
    message.destroy!

    expect { worker.perform(id) }.to_not raise_error
    expect(redraws).to be_empty
  end

  it 'leaves the shared worker alone: it still downloads without redrawing anything' do
    urls.each { |url| serve(url) }

    RedownloadMediaWorker.new.perform(message.media_attachments.first.id)

    expect(redraws).to be_empty
    expect(message.media_attachments.reload.first.needs_redownload?).to be(false)
  end
end
