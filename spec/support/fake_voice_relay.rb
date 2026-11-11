# frozen_string_literal: true

class FakeVoiceRelay
  include WebMock::API

  BASE = '/voice-relay/v1'

  attr_reader :origin, :allocations, :calls, :kicked
  attr_accessor :reserved_slots, :max_slots, :full, :participants, :events, :lease_state, :fail_with

  def initialize(origin = 'https://voice.example.org', max_slots: 100, reserved_slots: 0)
    @origin = origin
    @max_slots = max_slots
    @reserved_slots = reserved_slots
    @allocations = {}
    @calls = []
    @kicked = []
    @participants = []
    @events = []
    @full = false
    @lease_state = 'active'
    @fail_with = nil
  end

  def install
    stub_request(:any, %r{\A#{Regexp.escape(origin)}#{BASE}/}).to_return { |request| respond(request) }
    self
  end

  def provider
    Fabricate(:voice_relay_provider, origin:).tap { |provider| provider.update_columns(validated: true, capacity:) }
  end

  def capacity
    {
      'protocolVersion' => 1, 'enabled' => true, 'accepting' => true, 'maxSlots' => max_slots, 'reservedSlots' => reserved_slots,
      'remainingSlots' => max_slots - reserved_slots, 'remainingRooms' => full ? 0 : 5, 'allowScreenShare' => true, 'mediaProvider' => origin,
      'capabilities' => { 'cancelPending' => true, 'includeIceServers' => true }
    }
  end

  def called?(method, path)
    calls.include?([method, path])
  end

  def participant(account, session_id: 'PA_1', **attributes)
    {
      'identity' => ActivityPub::TagManager.instance.uri_for(account), 'userId' => account.id.to_s, 'sessionId' => session_id,
      'screenSharing' => false, 'allowScreenShare' => true, 'micTrackSid' => nil
    }.merge(attributes)
  end

  private

  def respond(request)
    uri = Addressable::URI.parse(request.uri.to_s)
    path = uri.path.delete_prefix(BASE)
    body = request.body.present? ? JSON.parse(request.body) : {}
    calls << [request.method, path]

    return json(fail_with.last, status: fail_with.first) if fail_with

    route(request.method, path, uri.query_values || {}, body)
  end

  def route(method, path, query, body)
    case [method, path]
    in [:get, '/capacity'] then json(capacity)
    in [:get, '/allocations'] then lookup(query)
    in [:post, '/allocations'] then allocate(body)
    in [:post, '/allocations/cancel'] then json({ state: 'ended' })
    in [:get, '/events'] then json({ events:, cursor: "c#{calls.size}", gap: false })
    else
      match = %r{\A/allocations/([^/]+)(/.*)?\z}.match(path)
      match ? allocation_route(method, match[1], match[2].to_s, body) : json({ code: 'NOT_FOUND' }, status: 404)
    end
  end

  def allocation_route(method, id, suffix, body)
    allocation = allocations[id]
    return json({ code: 'NOT_FOUND' }, status: 404) if allocation.nil?

    case [method, suffix]
    in [:post, '/join'] then join(allocation, body)
    in [:post, '/lease'] then lease(allocation)
    in [:get, '/snapshot'] then json({ allocationId: id, generation: allocation['generation'], state: allocation['state'], participants:, revision: calls.size.to_s })
    in [:delete, ''] then json(allocation.merge('state' => 'ended').tap { allocations[id]['state'] = 'ended' })
    in [:post, '/participants/kick']
      kicked << body['identity']
      participants.reject! { |participant| participant['identity'] == body['identity'] }
      json({ accepted: true })
    in [:post, '/participants/mute' | '/participants/status' | '/participants/permissions'] then json({ accepted: true })
    else json({ code: 'NOT_FOUND' }, status: 404)
    end
  end

  def lookup(query)
    allocation = allocations.values.find { |value| value['roomKey'] == query['roomKey'] && value['generation'] == query['generation'] }
    allocation ? json(allocation) : json({ code: 'NOT_FOUND' }, status: 404)
  end

  def allocate(body)
    return json({ code: 'CAPACITY_EXCEEDED' }, status: 429) if full

    existing = allocations.values.find { |value| value['roomKey'] == body['roomKey'] && value['generation'] == body['generation'] }
    return json(existing) if existing

    id = "alloc-#{allocations.size + 1}"
    allocations[id] = {
      'id' => id, 'clientId' => 'client', 'roomKey' => body['roomKey'], 'generation' => body['generation'], 'reservedSlots' => body['slots'],
      'leaseExpiresAt' => 2.minutes.from_now.iso8601, 'state' => 'active', 'createdAt' => Time.now.utc.iso8601
    }
    json(allocations[id])
  end

  def join(allocation, body)
    json({
      token: "lk-token-#{body['userId']}", allocationId: allocation['id'], generation: allocation['generation'], mediaProvider: origin,
      iceServers: [{ urls: ['turn:turn.example.org:3478'], username: 'u', credential: 'c' }],
      screenShareLimits: { maxWidth: 1920, maxHeight: 1080, maxFrameRate: 30, maxBitrate: 2_500_000 }
    })
  end

  def lease(allocation)
    allocation['state'] = lease_state
    json(allocation)
  end

  def json(value, status: 200)
    { status:, body: value.to_json, headers: { 'Content-Type' => 'application/json' } }
  end
end
