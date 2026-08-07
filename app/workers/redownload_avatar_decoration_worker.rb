# frozen_string_literal: true

class RedownloadAvatarDecorationWorker
  include Sidekiq::Worker
  include ExponentialBackoff
  include Redisable

  sidekiq_options queue: 'pull', retry: 3

  ACCOUNT_LIMIT = 4
  DOMAIN_LIMIT = 32
  BUDGET_PERIOD = 1.hour.to_i
  DEDUPLICATION_TTL = 1.hour.to_i

  class << self
    def enqueue(id, account_id: nil)
      decoration = AvatarDecoration.find_by(id: id)
      return false unless decoration&.image_repairable?

      key = deduplication_key(decoration)
      queued = RedisConnection.with { |redis| redis.set(key, 1, nx: true, ex: DEDUPLICATION_TTL) }
      return false unless queued

      perform_async(id, account_id)
      true
    rescue
      RedisConnection.with { |redis| redis.del(key) } if key
      raise
    end

    def deduplication_key(decoration)
      digest = Digest::SHA256.hexdigest(decoration.image_remote_url.to_s)
      "avatar_decoration_download:queued:#{decoration.id}:#{digest}"
    end
  end

  def perform(id, account_id = nil)
    decoration = AvatarDecoration.find(id)

    return unless decoration.image_repairable?
    return if decoration.host.present? && AvatarDecorationDomainBlock.blocked?(decoration.host)
    return unless within_download_budget?(decoration.host, account_id)

    decoration.repair_image!
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def within_download_budget?(host, account_id)
    bucket = Time.now.to_i / BUDGET_PERIOD
    keys = ["avatar_decoration_download:domain:#{host}:#{bucket}"]
    limits = [DOMAIN_LIMIT]
    if account_id.present?
      keys << "avatar_decoration_download:account:#{account_id}:#{bucket}"
      limits << ACCOUNT_LIMIT
    end

    script = <<~LUA
      for index, key in ipairs(KEYS) do
        local count = tonumber(redis.call('get', key) or '0')
        if count >= tonumber(ARGV[index]) then return 0 end
      end
      for index, key in ipairs(KEYS) do
        redis.call('incr', key)
        redis.call('expire', key, ARGV[#KEYS + 1])
      end
      return 1
    LUA

    redis.eval(script, keys: keys, argv: limits + [BUDGET_PERIOD + 60]) == 1
  end
end
