# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat attachments and the media proxy limit' do
  include_context 'with an open chat policy'

  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:reader) { Fabricate(:user) }
  let(:cherry) { Fabricate(:account, domain: 'cherry.test', uri: 'https://cherry.test/users/nari', inbox_url: 'https://cherry.test/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.update!(uri: "https://cb6e6126.ngrok.io/chat/rooms/#{record.id}")
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: reader.account)
      record.memberships.create!(account: cherry)
    end
  end
  let(:period) { 10.minutes }
  let(:general_limit) { 100 }
  let(:server_ip) { '198.51.100.7' }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: reader.id, scopes: 'read write') }

  # Rack::Attack periods are not rolling, so every example starts at the beginning of one.
  before do
    travel_to Time.zone.at(((Time.now.to_i / period.seconds).to_i + 1) * period.seconds)
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    room
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def message_with_attachments(count)
    media = Array.new(count) { Fabricate(:media_attachment, account: owner, status: nil) }
    service.create_message(owner, room, text: 'look', media_ids: media.map(&:id))
  end

  def fetch(url, ip)
    uri = URI.parse(url)
    get [uri.path, uri.query].compact.join('?'), headers: { 'REMOTE_ADDR' => ip }
    response.status
  end

  def media_proxy_count(ip)
    Rack::Attack.cache.read("#{(Time.now.to_i / period.seconds).to_i}:throttle_media_proxy:#{ip}") || 0
  end

  def fill_general_limit(ip)
    general_limit.times { Rack::Attack.cache.count("throttle_media_proxy:#{ip}", period) }
  end

  describe 'another server fetching attachments' do
    # The very addresses in the activities this server sends to that server.
    def delivered_urls(message)
      Sharlayan::ChatFederation::Payload.for_domain(Sharlayan::ChatFederation::Payload.create(message), message, 'cherry.test').dig('object', 'attachment').pluck('url')
    end

    it 'gets every attachment of more messages than the general limit would allow' do
      urls = Array.new(26) { message_with_attachments(4) }.flat_map { |message| delivered_urls(message) }

      statuses = urls.map { |url| fetch(url, server_ip) }

      expect(statuses.size).to be > general_limit
      expect(statuses).to all(satisfy { |status| [200, 302].include?(status) })
    end

    it 'does not use up what the general limit allows others at that address' do
      url = delivered_urls(message_with_attachments(1)).first

      expect { fetch(url, server_ip) }.to_not(change { media_proxy_count(server_ip) })
    end
  end

  describe 'a browser opening a conversation with many pictures' do
    it 'loads every picture it was given, far past the general limit' do
      26.times { message_with_attachments(4) }
      get "/api/v1/chat/conversations/#{room.id}/messages", params: { limit: 40 }, headers: { 'Authorization' => "Bearer #{token.token}", 'REMOTE_ADDR' => '203.0.113.9' }
      urls = response.parsed_body.flat_map { |message| message[:media_attachments].flat_map { |media| [media[:preview_url], media[:url]] } }

      statuses = urls.map { |url| fetch(url, '203.0.113.9') }

      expect(statuses.size).to be > general_limit
      expect(statuses).to all(satisfy { |status| [200, 302].include?(status) })
    end
  end

  describe 'requests that do not hold a valid token for the attachment' do
    let(:ip) { '203.0.113.20' }
    let(:media) { message_with_attachments(1).media_attachments.first }
    let(:other_media) { message_with_attachments(1).media_attachments.first }

    before { fill_general_limit(ip) }

    it 'keeps a forged chat_token under the general limit' do
      expect(fetch("/media_proxy/#{media.id}/original?chat_token=forged", ip)).to eq(429)
    end

    it 'keeps a forged server token under the general limit' do
      expect(fetch("/media_proxy/#{media.id}/original?token=forged", ip)).to eq(429)
    end

    it 'keeps a token copied from another signature under the general limit' do
      forged = "#{Sharlayan::ChatMediaToken.generate(media, reader.account).split('--').first}--#{'0' * 64}"

      expect(fetch("/media_proxy/#{media.id}/original?chat_token=#{forged}", ip)).to eq(429)
    end

    it 'keeps a valid token used for another attachment under the general limit' do
      expect(fetch("/media_proxy/#{other_media.id}/original?chat_token=#{Sharlayan::ChatMediaToken.generate(media, reader.account)}", ip)).to eq(429)
      expect(fetch("/media_proxy/#{other_media.id}/original?token=#{Sharlayan::ChatFederation::MediaToken.generate(media, domain: 'cherry.test')}", ip)).to eq(429)
    end

    it 'keeps an expired token under the general limit' do
      expired = Sharlayan::ChatMediaToken.generate(media, reader.account)
      travel 11.minutes
      fill_general_limit(ip)

      expect(fetch("/media_proxy/#{media.id}/original?chat_token=#{expired}", ip)).to eq(429)
    end

    it 'keeps a token sent in an unexpected shape under the general limit' do
      expect(fetch("/media_proxy/#{media.id}/original?chat_token[]=forged", ip)).to eq(429)
      expect(fetch("/media_proxy/#{media.id}/original?chat_token=%FF%FE", ip)).to eq(429)
    end

    it 'keeps a request without a token under the general limit' do
      expect(fetch("/media_proxy/#{media.id}/original", ip)).to eq(429)
    end

    it 'does not let a valid token past the limit on the other proxy path' do
      valid = Sharlayan::ChatMediaToken.generate(media, reader.account)

      expect(fetch("/proxy/image.webp?url=https%3A%2F%2Fremote.example%2Fi.webp&chat_token=#{valid}", ip)).to eq(429)
    end
  end

  describe 'whether a browser may keep the answer' do
    let(:ip) { '203.0.113.40' }
    let(:media) { message_with_attachments(1).media_attachments.first }

    def cache_control_of(url)
      fetch(url, ip)
      response.headers['Cache-Control']
    end

    it 'may keep it privately for as long as the token stays the same' do
      url = "/media_proxy/#{media.id}/small?chat_token=#{Sharlayan::ChatMediaToken.generate(media, reader.account)}"

      expect(cache_control_of(url)).to include('private', 'max-age=60')
      expect(response).to have_http_status(302)
      expect(response.headers['Cache-Control']).to_not include('no-store', 'public')
    end

    it 'may not keep a refusal' do
      expect(cache_control_of("/media_proxy/#{media.id}/small?chat_token=forged")).to include('no-store')
      expect(response).to have_http_status(404)
    end

    it 'may not keep the answer to a token of someone who has left' do
      url = "/media_proxy/#{media.id}/small?chat_token=#{Sharlayan::ChatMediaToken.generate(media, reader.account)}"
      room.memberships.find_by!(account: reader.account).destroy!

      expect(cache_control_of(url)).to include('no-store')
      expect(response).to have_http_status(404)
    end

    it 'may not keep what another server is given' do
      url = "/media_proxy/#{media.id}/original?token=#{Sharlayan::ChatFederation::MediaToken.generate(media, domain: 'cherry.test')}"

      expect(cache_control_of(url)).to include('no-store')
      expect(response).to have_http_status(302)
    end

    it 'may not keep a failure to fetch the file from another server' do
      remote_media = MediaAttachment.create!(account: cherry, remote_url: 'https://cherry.test/files/1', file_content_type: 'image/png')
      message = room.messages.create!(account: cherry, text: 'look')
      message.media_attachments << remote_media
      stub_request(:get, 'https://cherry.test/files/1').to_return(status: 404)

      expect(cache_control_of("/media_proxy/#{remote_media.id}/small?chat_token=#{Sharlayan::ChatMediaToken.generate(remote_media, reader.account)}")).to include('no-store')
      expect(response).to have_http_status(404)
    end
  end

  describe 'valid tokens have a limit of their own' do
    let(:ip) { '203.0.113.30' }
    let(:media) { message_with_attachments(1).media_attachments.first }
    let(:limit) { Rack::Attack.throttles.fetch('throttle_chat_media').limit }

    it 'is larger than the general one' do
      expect(limit).to be > general_limit
    end

    it 'stops a valid token past that limit and allows it again in the next period' do
      url = "/media_proxy/#{media.id}/original?chat_token=#{Sharlayan::ChatMediaToken.generate(media, reader.account)}"
      limit.times { Rack::Attack.cache.count("throttle_chat_media:#{ip}", period) }

      expect(fetch(url, ip)).to eq(429)

      travel period
      fresh = "/media_proxy/#{media.id}/original?chat_token=#{Sharlayan::ChatMediaToken.generate(media, reader.account)}"
      expect(fetch(fresh, ip)).to eq(302)
    end
  end
end
