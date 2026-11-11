# frozen_string_literal: true

class Sharlayan::VoiceCallService
  include Lockable
  include Redisable
  extend Redisable

  class Unavailable < StandardError; end
  class Forbidden < StandardError; end
  class Removed < Forbidden; end

  Error = Sharlayan::VoiceRelay::Error
  Responses = Sharlayan::VoiceRelay::Responses

  LEASE_RENEW_AFTER = 25.seconds
  SNAPSHOT_REFRESH_AFTER = 60.seconds
  LOCK_AUTORELEASE = 1.minute
  ENDED_RETENTION = 7.days
  PROVIDER_COOLDOWN = 10.seconds
  REMOVAL_BLOCK = 10.minutes
  MAX_SESSION_ID_LENGTH = 2048
  GONE_CODES = %w(NOT_FOUND ALLOCATION_CONFLICT ALLOCATION_ENDED).freeze

  class << self
    def enabled?
      Setting.chat_enabled && Setting.voice_call_enabled
    end

    def available?(conversation)
      return false unless enabled? && conversation.local? && !conversation.archived?

      conversation.chat_group? || conversation.accounts.all?(&:local?)
    end

    def joinable?(conversation)
      available?(conversation) && VoiceRelayProvider.usable.exists?
    end

    def slots_for(conversation)
      conversation.chat_direct? ? 2 : Setting.voice_call_max_participants.to_i.clamp(2, 100)
    end

    def identity_for(account)
      ActivityPub::TagManager.instance.uri_for(account)
    end

    def room_key_for(conversation)
      "#{Sharlayan::VoiceRelay::Origin.local}/chat/rooms/#{conversation.id}"
    end

    def signal_url
      ENV.fetch('VOICE_SIGNAL_URL') { "wss://#{Rails.configuration.x.web_domain}/voice-signal" }
    end

    def permitted?(account, privilege = :join_voice_calls)
      return remote_permitted?(account, privilege) if account.present? && !account.local?

      user = account&.local? && account.user
      return false unless user&.functional?
      return false if privilege == :share_screens && !Setting.voice_call_screen_share_enabled

      user.role.can_extra?(:join_voice_calls) && user.role.can_extra?(privilege)
    end

    def remote_permitted?(account, privilege)
      return false if privilege == :share_screens && !Setting.voice_call_screen_share_enabled

      Sharlayan::VoiceCallFederation.remote_account_permitted?(account)
    end

    def participant_accounts(records)
      ids = Array(records).flat_map { |record| participants_of(record) }.pluck('user_id').uniq
      Account.where(id: ids).includes(:account_stat, :user).index_by { |account| account.id.to_s }
    end

    def participants_of(record)
      case record
      when VoiceCallAllocation then record.active? ? record.participants : []
      when VoiceCallRemoteState then record.current_participants
      else []
      end
    end

    def state_for(conversation, allocation = :unset, relay_usable: nil, accounts: nil, remote_state: :unset)
      return remote_state_for(conversation, remote_state, accounts:) unless conversation.local?

      allocation = VoiceCallAllocation.find_by(chat_conversation_id: conversation.id) if allocation == :unset
      relay_usable = VoiceRelayProvider.usable.exists? if relay_usable.nil?
      participants = participants_of(allocation)
      accounts ||= participant_accounts(allocation)

      {
        conversation_id: conversation.id.to_s,
        available: relay_usable && available?(conversation),
        active: participants.any?,
        unavailable: allocation&.active? ? allocation.unavailable? : false,
        max_participants: allocation&.active? ? allocation.slots : slots_for(conversation),
        updated_at: allocation ? (allocation.updated_at.to_r * 1000).to_i : 0,
        participants: serialize_participants(participants, accounts),
      }
    end

    def remote_state_for(conversation, remote_state, accounts:)
      remote_state = VoiceCallRemoteState.find_by(chat_conversation_id: conversation.id) if remote_state == :unset
      participants = participants_of(remote_state)
      accounts ||= participant_accounts(remote_state)

      {
        conversation_id: conversation.id.to_s,
        available: remote_available?(conversation),
        active: participants.any?,
        unavailable: false,
        max_participants: slots_for(conversation),
        updated_at: remote_state&.remote_updated_at || 0,
        participants: serialize_participants(participants, accounts),
      }
    end

    def remote_available?(conversation)
      owner = conversation.owner_account
      Sharlayan::VoiceCallFederation.remote_join_enabled? && !conversation.local? && !conversation.archived? &&
        owner.present? && !owner.local? && !owner.unavailable? && !DomainBlock.blocked?(owner.domain)
    end

    def serialize_participants(participants, accounts)
      participants.filter_map do |participant|
        account = accounts[participant['user_id']]
        next if account.nil?

        {
          identity: participant['identity'],
          account_id: participant['user_id'],
          account: REST::AccountSerializer.new(account).as_json,
          screen_sharing: participant['screen_sharing'],
          mic_muted: participant['mic_muted'],
          deafened: participant['deafened'],
        }
      end
    end

    def publish_state(conversation, payload = state_for(conversation))
      json = JSON.generate(payload)
      account_ids = conversation.memberships.joins(:account).merge(Account.local).pluck(:account_id)

      ActiveRecord.after_all_transactions_commit do
        account_ids.each do |account_id|
          redis.publish("timeline:#{account_id}", JSON.generate(event: 'chat.voice_state', payload: json))
        end
        yield if block_given?
      end
    end
  end

  def join(account, conversation, screen_share: true)
    return join_remote(account, conversation, screen_share:) unless conversation.local?

    raise Unavailable unless self.class.joinable?(conversation) && self.class.permitted?(account)

    allocation, credentials = with_redis_lock(conversation_lock_key(conversation.id), autorelease: LOCK_AUTORELEASE) do
      require_member!(conversation, account)
      raise Removed if removed_from_call?(conversation, account)

      allocation = ensure_allocation(conversation)

      begin
        [allocation, request_join(allocation, account, screen_share:)]
      rescue Error => e
        raise unless gone?(e)

        finish(allocation)
        allocation = ensure_allocation(conversation)
        [allocation, request_join(allocation, account, screen_share:)]
      end
    end

    VoiceCallEventsWorker.perform_async(allocation.voice_relay_provider_id)
    credentials
  end

  def report_status(account, conversation, session_id:, mic_muted:, deafened:)
    raise Mastodon::InvalidParameterError, "session_id must be a string of up to #{MAX_SESSION_ID_LENGTH} characters" unless session_id.is_a?(String) && session_id.length.between?(1, MAX_SESSION_ID_LENGTH)

    return report_remote_status(account, conversation, session_id:, mic_muted:, deafened:) unless conversation.local?

    with_active_allocation(conversation) do |allocation|
      require_member!(conversation, account)

      accepted = Responses.accepted(participant_request(allocation, 'status', identity: self.class.identity_for(account), sessionId: session_id, micMuted: mic_muted, deafened: deafened))
      VoiceCallEventsWorker.perform_async(allocation.voice_relay_provider_id) if accepted
      accepted
    end
  end

  def join_remote(account, conversation, screen_share:)
    raise Unavailable unless account.local? && self.class.permitted?(account)

    require_member!(conversation, account)
    Sharlayan::VoiceCallFederation::RemoteJoin.new(account, conversation).join(screen_share:)
  end

  def report_remote_status(account, conversation, session_id:, mic_muted:, deafened:)
    raise Unavailable unless account.local? && self.class.permitted?(account)

    require_member!(conversation, account)
    Sharlayan::VoiceCallFederation::RemoteJoin.new(account, conversation).report_status(session_id:, mic_muted:, deafened:)
  end

  def kick(actor, conversation, target)
    moderate(actor, conversation, target) do |allocation|
      redis.set(removal_key(conversation.id, target.id), allocation.generation, ex: REMOVAL_BLOCK.to_i)
      kicked = remove_identities(allocation, identities_of(allocation, target.id.to_s, target))
      refresh(allocation)
      kicked
    end
  end

  def mute(actor, conversation, target)
    moderate(actor, conversation, target) do |allocation|
      Responses.accepted(participant_request(allocation, 'mute', identity: self.class.identity_for(target)))
    end
  end

  def revoke(conversation_id, account_id)
    with_redis_lock(conversation_lock_key(conversation_id), autorelease: LOCK_AUTORELEASE) do
      allocation = VoiceCallAllocation.active.find_by(chat_conversation_id: conversation_id)
      next if allocation.nil?

      account = Account.find_by(id: account_id)
      member = account && ChatMembership.exists?(chat_conversation_id: conversation_id, account_id: account_id)
      next if member

      remove_identities(allocation, identities_of(allocation, account_id.to_s, account))
      refresh(allocation)
    end
  end

  def end_call(allocation)
    with_redis_lock(allocation.lock_key, autorelease: LOCK_AUTORELEASE) do
      allocation.reload
      finish(allocation) unless allocation.ended?
    end
  end

  def maintain
    VoiceCallAllocation.unfinished.includes(:voice_relay_provider, :chat_conversation).find_each do |allocation|
      maintain_allocation(allocation)
    end

    VoiceCallAllocation.active.distinct.pluck(:voice_relay_provider_id).each do |provider_id|
      VoiceCallEventsWorker.perform_async(provider_id)
    end

    VoiceCallAllocation.active.where.not(chat_conversation_id: nil).includes(:chat_conversation).find_each do |allocation|
      Sharlayan::VoiceCallFederation::Outgoing.schedule(allocation.chat_conversation) if allocation.participants.any?
    end

    VoiceCallAllocation.where(state: 'ended', chat_conversation_id: nil, updated_at: ...ENDED_RETENTION.ago).in_batches.delete_all
    VoiceCallRemoteSession.expired.in_batches.delete_all
  end

  def poll_events(provider)
    allocations = provider.voice_call_allocations.active.to_a
    return false if allocations.empty?

    feed = fetch_events(provider, allocations)
    return true if feed.nil?

    failed = false
    allocations.each do |allocation|
      next unless feed[:gap] || refresh_due?(allocation) || feed[:touched].include?([allocation.remote_id, allocation.generation])

      with_redis_lock(allocation.lock_key, autorelease: LOCK_AUTORELEASE) do
        allocation.reload
        refresh(allocation) if allocation.active?
      end
    rescue Mastodon::RaceConditionError
      failed = true
    rescue Error => e
      failed = true
      allocation.update_columns(unavailable: true)
      record_provider_error(provider, e)
    end

    provider.update_columns(events_cursor: feed[:cursor]) unless failed
    true
  end

  private

  def fetch_events(provider, allocations)
    cursor = provider.events_cursor.presence
    Responses.events(provider.client.request(:get, cursor ? "/events?#{URI.encode_www_form(cursor:)}" : '/events'))
  rescue Error => e
    record_provider_error(provider, e)
    VoiceCallAllocation.where(id: allocations.map(&:id)).update_all(unavailable: true)
    nil
  end

  def conversation_lock_key(conversation_id)
    "voice_call:#{conversation_id}"
  end

  def removal_key(conversation_id, account_id)
    "voice_call:removed:#{conversation_id}:#{account_id}"
  end

  def removed_from_call?(conversation, account)
    generation = redis.get(removal_key(conversation.id, account.id))
    generation.present? && VoiceCallAllocation.unfinished.exists?(chat_conversation_id: conversation.id, generation:)
  end

  def require_member!(conversation, account)
    raise Forbidden unless ChatMembership.exists?(chat_conversation_id: conversation.id, account_id: account.id)
  end

  def require_owner!(conversation, account)
    raise Forbidden unless ChatMembership.exists?(chat_conversation_id: conversation.id, account_id: account.id, role: :owner)
  end

  def moderate(actor, conversation, target)
    raise Forbidden if actor.id == target.id

    with_active_allocation(conversation) do |allocation|
      require_owner!(conversation, actor)
      yield allocation
    end
  end

  def with_active_allocation(conversation)
    with_redis_lock(conversation_lock_key(conversation.id), autorelease: LOCK_AUTORELEASE) do
      allocation = VoiceCallAllocation.active.find_by(chat_conversation_id: conversation.id)
      raise Error.new('ALLOCATION_CONFLICT', 409) if allocation.nil?

      yield allocation
    end
  end

  def gone?(error)
    GONE_CODES.include?(error.code)
  end

  def ensure_allocation(conversation)
    allocation = VoiceCallAllocation.find_by(chat_conversation_id: conversation.id)
    return allocation if allocation && resume(allocation)

    slots = self.class.slots_for(conversation)
    providers, outcomes = candidate_providers(slots)

    providers.each do |provider|
      allocation ||= VoiceCallAllocation.new(chat_conversation: conversation)
      allocation.update!(
        voice_relay_provider: provider, room_key: self.class.room_key_for(conversation), generation: SecureRandom.uuid,
        remote_id: nil, state: 'pending', slots:, revision: nil, participants: [], unavailable: false, renewed_at: nil, refreshed_at: nil
      )

      begin
        reserve(allocation, fresh: true)
        return allocation
      rescue Error => e
        raise unless e.code == 'CAPACITY_EXCEEDED'

        allocation.update!(state: 'ended')
      end
    end

    raise Error.new('CAPACITY_EXCEEDED', 429) if outcomes.include?(:measured)
    raise Error.new('CLIENT_DISABLED', 403) if outcomes.any? && outcomes.all?(:disabled)

    raise Error, 'PROVIDER_UNAVAILABLE'
  end

  def resume(allocation)
    renew(allocation, force: true) if allocation.active?

    if allocation.pending?
      begin
        reserve(allocation, fresh: false)
      rescue Error => e
        raise unless %w(CAPACITY_EXCEEDED ALLOCATION_ENDED).include?(e.code)

        terminate_pending(allocation) unless allocation.ended?
      end
    end

    finish(allocation) if allocation.ending?

    allocation.active?
  end

  def candidate_providers(slots)
    outcomes = []

    ranked = VoiceRelayProvider.usable.order(:id).filter_map do |provider|
      if cooling_down?(provider)
        outcomes << :unavailable
        next
      end

      capacity = provider.client.capacity
      VoiceRelayProvider.where(id: provider.id, credential_version: provider.credential_version)
        .update_all(capacity:, validated: capacity['enabled'], last_error: nil, last_checked_at: Time.now.utc, updated_at: Time.now.utc)

      unless capacity['enabled'] && capacity['accepting']
        outcomes << (capacity['enabled'] ? :unavailable : :disabled)
        next
      end

      outcomes << :measured
      next unless capacity['remainingSlots'] >= slots && capacity['remainingRooms'].positive?

      [provider, capacity['reservedSlots'].fdiv(capacity['maxSlots']), rand]
    rescue Error => e
      record_provider_error(provider, e)
      start_cooldown(provider)
      outcomes << (e.revoked? ? :disabled : :unavailable)
      nil
    end

    [ranked.sort_by { |_, ratio, tie| [ratio, tie] }.map(&:first), outcomes]
  end

  def reserve(allocation, fresh:)
    client = allocation.voice_relay_provider.client
    existing = fresh ? nil : lookup(allocation)

    if existing&.dig('state') == 'ended'
      allocation.update!(remote_id: existing['id'], state: 'ended', participants: [])
      raise Error.new('ALLOCATION_ENDED', 409)
    end

    result = existing
    if existing.nil? || existing['state'] == 'pending'
      body = { roomKey: allocation.room_key, generation: allocation.generation, slots: allocation.slots }
      result = Responses.allocation(client.request(:post, '/allocations', body), generation: allocation.generation, slots: allocation.slots)
    end

    allocation.remote_id = result['id']

    case result['state']
    when 'active'
      allocation.update!(state: 'active', renewed_at: Time.now.utc, unavailable: false)
    when 'pending'
      allocation.save!
      raise Error, 'PROVIDER_UNAVAILABLE'
    else
      allocation.update!(state: 'ended', participants: [])
      raise Error.new('ALLOCATION_ENDED', 409)
    end
  end

  def lookup(allocation)
    query = URI.encode_www_form(roomKey: allocation.room_key, generation: allocation.generation)
    Responses.allocation(allocation.voice_relay_provider.client.request(:get, "/allocations?#{query}"), generation: allocation.generation, slots: allocation.slots)
  rescue Error => e
    raise unless e.status == 404

    nil
  end

  def renew(allocation, force: false)
    return true if !force && allocation.renewed_at && allocation.renewed_at > LEASE_RENEW_AFTER.ago

    result = Responses.allocation(allocation.voice_relay_provider.client.request(:post, allocation.remote_path('/lease'), {}), generation: allocation.generation, slots: allocation.slots)
    raise Responses.invalid unless result['id'] == allocation.remote_id

    case result['state']
    when 'active'
      allocation.update!(renewed_at: Time.now.utc, unavailable: false)
      true
    when 'ended'
      mark_ended(allocation)
      false
    else
      allocation.update!(state: 'ending')
      false
    end
  rescue Error => e
    raise unless gone?(e)

    allocation.update!(state: 'ending')
    false
  end

  def finish(allocation)
    return terminate_pending(allocation) if allocation.pending?

    allocation.update!(state: 'ending')
    Responses.ended(allocation.voice_relay_provider.client.request(:delete, allocation.remote_path), allocation)
    mark_ended(allocation)
  rescue Error => e
    raise unless e.code == 'NOT_FOUND'

    mark_ended(allocation)
  end

  def terminate_pending(allocation)
    client = allocation.voice_relay_provider.client
    existing = lookup(allocation)

    if existing
      allocation.update!(remote_id: existing['id'])

      unless existing['state'] == 'ended'
        allocation.update!(state: 'ending')
        Responses.ended(client.request(:delete, allocation.remote_path), allocation)
      end
    else
      raise Error, 'PROVIDER_UNAVAILABLE' unless client.capacity.dig('capabilities', 'cancelPending')

      result = client.request(:post, '/allocations/cancel', { roomKey: allocation.room_key, generation: allocation.generation })
      raise Responses.invalid unless result['state'] == 'ended'
    end

    mark_ended(allocation)
  end

  def mark_ended(allocation)
    had_participants = allocation.participants.any?
    allocation.update!(state: 'ended', participants: [], unavailable: false)
    broadcast(allocation) if had_participants
  end

  def request_join(allocation, account, screen_share: true)
    provider = allocation.voice_relay_provider
    identity = self.class.identity_for(account)
    allow_screen_share = screen_share && self.class.permitted?(account, :share_screens) && provider.capacity['allowScreenShare'] == true

    body = { identity:, userId: account.id.to_s, allowScreenShare: allow_screen_share }
    credentials = Responses.join(provider.client.request(:post, allocation.remote_path('/join'), body), allocation)

    credentials.merge(
      url: self.class.signal_url,
      identity:,
      allow_screen_share:,
      max_participants: allocation.slots
    )
  end

  def participant_request(allocation, action, body)
    allocation.voice_relay_provider.client.request(:post, allocation.remote_path("/participants/#{action}"), body)
  end

  def identities_of(allocation, account_id, account)
    identities = allocation.participants.select { |participant| participant['user_id'] == account_id }.pluck('identity')
    identities << self.class.identity_for(account) if account
    identities.uniq
  end

  def remove_identities(allocation, identities)
    identities.map { |identity| Responses.accepted(participant_request(allocation, 'kick', identity:)) }.any?
  end

  def refresh_due?(allocation)
    allocation.unavailable? || allocation.refreshed_at.nil? || allocation.refreshed_at < SNAPSHOT_REFRESH_AFTER.ago
  end

  def refresh(allocation)
    snapshot = Responses.snapshot(allocation.voice_relay_provider.client.request(:get, allocation.remote_path('/snapshot')), allocation)
    return if allocation.revision.present? && snapshot[:revision].to_i < allocation.revision.to_i

    return mark_ended(allocation) if snapshot[:state] == 'ended'

    participants = admitted_participants(allocation, snapshot[:participants])
    changed = participants != allocation.participants

    allocation.update!(participants:, revision: snapshot[:revision], refreshed_at: Time.now.utc, unavailable: false)
    broadcast(allocation) if changed
  end

  def admitted_participants(allocation, participants)
    permissions = allocation.chat_conversation_id ? member_permissions(allocation.chat_conversation_id) : {}
    refused = []
    restricted = {}

    admitted = participants.filter_map do |participant|
      permission = permissions[participant['user_id']]
      if permission.nil?
        refused << participant['identity']
        nil
      elsif permission == :share_screens || !(participant['screen_sharing'] || participant['allow_screen_share'])
        participant
      else
        identity = participant['identity']
        restricted[identity] = restrict_screen_share(allocation, identity) unless restricted.key?(identity)
        participant.merge('screen_sharing' => false, 'allow_screen_share' => false) if restricted[identity]
      end
    end

    remove_identities(allocation, refused.uniq) if refused.any?
    admitted
  end

  def restrict_screen_share(allocation, identity)
    Responses.accepted(participant_request(allocation, 'permissions', identity:, allowScreenShare: false))
  rescue Error => e
    raise unless e.code == 'NOT_FOUND'

    remove_identities(allocation, [identity])
    false
  end

  def member_permissions(conversation_id)
    ActiveRecord::Base.cache do
      accounts = Account.where(id: ChatMembership.where(chat_conversation_id: conversation_id).select(:account_id)).includes(user: :role)
      accounts.each_with_object({}) do |account, permissions|
        next unless self.class.permitted?(account)

        permissions[account.id.to_s] = self.class.permitted?(account, :share_screens) ? :share_screens : :join_voice_calls
      end
    end
  end

  def cooling_down?(provider)
    redis.exists?("voice_relay:cooldown:#{provider.id}")
  end

  def start_cooldown(provider)
    redis.set("voice_relay:cooldown:#{provider.id}", '1', ex: PROVIDER_COOLDOWN.to_i)
  end

  def maintain_allocation(allocation)
    with_redis_lock(allocation.lock_key, autorelease: LOCK_AUTORELEASE, raise_on_failure: false) do
      allocation.reload
      next if allocation.ended?

      conversation = allocation.chat_conversation
      if conversation.nil? || !self.class.available?(conversation) || allocation.ending?
        finish(allocation)
      elsif allocation.pending?
        resume(allocation)
      else
        renew_or_close(allocation)
      end
    end
  rescue Error => e
    allocation.update_columns(unavailable: true)
    record_provider_error(allocation.voice_relay_provider, e)
  end

  def renew_or_close(allocation)
    renew(allocation)
    finish(allocation) if allocation.ending?
  rescue Error => e
    raise unless e.revoked?

    record_provider_error(allocation.voice_relay_provider, e)
    finish(allocation)
  end

  def record_provider_error(provider, error)
    provider.update_columns(VoiceRelayProvider.error_attributes(error, revoked_at: provider.revoked_at))
  end

  def broadcast(allocation)
    conversation = allocation.chat_conversation
    return if conversation.nil?

    self.class.publish_state(conversation, self.class.state_for(conversation, allocation)) do
      Sharlayan::VoiceCallFederation::Outgoing.schedule(conversation)
    end
  end
end
