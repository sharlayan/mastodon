# frozen_string_literal: true

class ActivityPub::FetchRemoteAccountService < ActivityPub::FetchRemoteActorService
  # Does a WebFinger roundtrip on each call, unless `only_key` is true
  def call(uri, prefetched_body: nil, break_on_redirect: false, only_key: false, suppress_errors: true, request_id: nil)
    actor = super

    if actor.is_a?(Account) && actor.remote?
      begin
        ensure_instance_metadata(actor)
      rescue => e
        Rails.logger.warn "Failed to enqueue instance metadata update for #{actor.domain}: #{e}"
      end
    end

    return actor if actor.nil? || actor.is_a?(Account)

    Rails.logger.debug { "Fetching account #{uri} failed: Expected Account, got #{actor.class.name}" }
    raise Error, "Expected Account, got #{actor.class.name}" unless suppress_errors
  end

  private

  def ensure_instance_metadata(account)
    domain = account.domain
    return if domain.blank?
    return if InstanceMetadata.exists?(domain: domain)

    InstanceMetadataUpdateWorker.perform_async(domain)
  end
end
