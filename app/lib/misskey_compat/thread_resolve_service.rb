# frozen_string_literal: true

class MisskeyCompat::ThreadResolveService
  include JsonLdHelper

  RETRY_MARKER_TTL = 30.minutes

  def call(status, on_behalf_of: nil)
    return status unless resolvable?(status)
    return status unless claim_attempt!(status)

    parent = resolve_parent(status, on_behalf_of)
    return status if parent.nil?

    status.update(thread: parent) if status.thread.nil?
    status.reload
  rescue
    status
  end

  private

  def resolvable?(status)
    status.present? && !status.local? && status.uri.present? && status.reply? && status.thread.nil?
  end

  def resolve_parent(status, on_behalf_of)
    json = fetch_resource(status.uri, on_behalf_of: on_behalf_of)
    return if json.blank?

    parent_uri = value_or_id(json['inReplyTo'])
    return if parent_uri.blank?

    ActivityPub::TagManager.instance.uri_to_resource(parent_uri, Status) ||
      FetchRemoteStatusService.new.call(parent_uri)
  end

  def claim_attempt!(status)
    Rails.cache.write(marker_key(status), true, expires_in: RETRY_MARKER_TTL, unless_exist: true)
  end

  def marker_key(status)
    "misskey_compat:thread_resolve:#{status.id}"
  end
end
