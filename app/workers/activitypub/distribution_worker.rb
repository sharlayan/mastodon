# frozen_string_literal: true

class ActivityPub::DistributionWorker < ActivityPub::RawDistributionWorker
  # Skip followers synchronization for accounts with a large number of followers,
  # as this is expensive and people with very large amounts of followers
  # necessarily have less control over them to begin with
  MAX_FOLLOWERS_FOR_SYNCHRONIZATION = 25_000

  # Distribute a new status or an edit of a status to all the places
  # where the status is supposed to go or where it was interacted with
  def perform(status_id)
    @status  = Status.find(status_id)
    @account = @status.account

    distribute!
  rescue ActiveRecord::RecordNotFound
    true
  end

  BRIDGE_DOMAIN = 'bsky.brid.gy'

  protected

  def distribute!
    return if inboxes.empty?

    bridge = bridge_inboxes
    primary = inboxes - bridge

    ActivityPub::DeliveryWorker.push_bulk(primary, limit: 1_000) do |inbox_url|
      [payload, @account.id, inbox_url, options]
    end

    return if bridge.empty?

    ActivityPub::DeliveryWorker.push_bulk(bridge, limit: 1_000) do |inbox_url|
      [bridge_payload, @account.id, inbox_url, options]
    end
  end

  def inboxes
    @inboxes ||= StatusReachFinder.new(@status).inboxes
  end

  def bridge_inboxes
    return [] unless promote_unlisted_to_bridge?

    @bridge_inboxes ||= inboxes.select { |url| bridge_inbox?(url) }
  end

  def promote_unlisted_to_bridge?
    @status.unlisted_visibility? && !@status.reblog? && @account.user&.setting_bridge_unlisted_to_bsky
  end

  def bridge_inbox?(url)
    host = Addressable::URI.parse(url).normalized_host
    host == BRIDGE_DOMAIN || host&.end_with?(".#{BRIDGE_DOMAIN}")
  rescue Addressable::URI::InvalidURIError
    false
  end

  def payload
    @payload ||= serialize_payload(@status, activity_serializer, serializer_options.merge(signer: @account)).to_json
  end

  def bridge_payload
    @bridge_payload ||= serialize_payload(@status, activity_serializer, serializer_options.merge(signer: @account, promote_to_public: true)).to_json
  end

  def activity_serializer
    @status.reblog? ? ActivityPub::AnnounceNoteSerializer : ActivityPub::CreateNoteSerializer
  end

  def serializer_options
    {}
  end

  def options
    { 'synchronize_followers' => @status.private_visibility? && @account.followers_count < MAX_FOLLOWERS_FOR_SYNCHRONIZATION }
  end
end
