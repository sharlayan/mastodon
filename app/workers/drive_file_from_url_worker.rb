# frozen_string_literal: true

class DriveFileFromURLWorker
  include Sidekiq::Worker
  include Redisable

  sidekiq_options queue: 'pull', retry: 3

  LOCK_TTL = 1.hour.to_i
  PROCESSING_TTL = 15.minutes.to_i

  class << self
    def enqueue(account_id, url, options = {})
      key = deduplication_key(account_id, url)
      queued = RedisConnection.with { |redis| redis.set(key, 1, nx: true, ex: LOCK_TTL) }
      return false unless queued

      perform_async(account_id, url, options)
      true
    rescue
      RedisConnection.with { |redis| redis.del(key) } if key
      raise
    end

    def deduplication_key(account_id, url)
      normalized = Addressable::URI.parse(url).normalize.to_s
      "drive_url_upload:queued:#{account_id}:#{Digest::SHA256.hexdigest(normalized)}"
    rescue Addressable::URI::InvalidURIError
      "drive_url_upload:queued:#{account_id}:#{Digest::SHA256.hexdigest(url.to_s)}"
    end
  end

  def perform(account_id, url, options = {})
    @preserve_deduplication_lock = false
    @processing_lock_acquired = false
    @processing_lock_token = nil
    account = Account.find_by(id: account_id)
    return if account.nil?

    unless acquire_processing_lock(account_id)
      self.class.perform_in(30.seconds, account_id, url, options)
      @preserve_deduplication_lock = true
      return
    end

    @options = options.with_indifferent_access
    return if quota_full?(account)

    candidate = account.drive_files.build(
      folder_id: @options[:folder_id].presence,
      sensitive: ActiveModel::Type::Boolean.new.cast(@options[:sensitive]),
      description: @options[:description]
    )

    return unless download_to(candidate, url)

    path = candidate.file.queued_for_write[:original]&.path
    return if path.blank?

    persist(account, candidate, url, Digest::SHA256.file(path).hexdigest, Digest::MD5.file(path).hexdigest)
  rescue Mastodon::ValidationError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("DriveFileFromUrlWorker(#{account_id}) skipped: #{e.message}")
  ensure
    release_locks(account_id, url)
  end

  private

  def download_to(candidate, url)
    parsed = Addressable::URI.parse(url).normalize
    return false unless %w(http https).include?(parsed.scheme) && parsed.host.present?

    Request.new(:get, url).perform do |response|
      raise Mastodon::UnexpectedResponseError, response unless (200...300).cover?(response.code)

      candidate.file = ResponseWithLimit.new(response, DriveFile.max_download_size)
    end

    candidate.file?
  rescue Mastodon::UnexpectedResponseError, Mastodon::HostValidationError, Mastodon::LengthValidationError, Addressable::URI::InvalidURIError, Paperclip::Error, *Mastodon::HTTP_CONNECTION_ERRORS => e
    Rails.logger.warn("DriveFileFromUrlWorker download failed for #{url}: #{e.message}")
    false
  end

  def persist(account, candidate, url, digest, md5)
    account.with_lock do
      existing = account.drive_files.find_by(sha256: digest)

      if existing
        existing.update!(
          folder_id: @options[:folder_id].presence || existing.folder_id,
          sensitive: ActiveModel::Type::Boolean.new.cast(@options[:sensitive]),
          description: @options[:description],
          created_at: Time.current
        )
      elsif !within_quota?(account, candidate.quota_storage_file_size)
        raise Mastodon::ValidationError, 'Drive storage quota exceeded'
      else
        candidate.sha256 = digest
        candidate.md5 = md5
        candidate.display_name = derived_name(url, candidate)
        candidate.save!
      end
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def within_quota?(account, incoming_size)
    quota = account.drive_quota_bytes
    return true if quota <= 0

    used = account.drive_files.sum(:storage_file_size).to_i
    used + incoming_size.to_i <= quota
  end

  def quota_full?(account)
    quota = account.drive_quota_bytes
    quota.positive? && account.drive_files.sum(:storage_file_size).to_i >= quota
  end

  def acquire_processing_lock(account_id)
    @processing_lock_token = SecureRandom.hex(16)
    @processing_lock_acquired = redis.set("drive_url_upload:processing:#{account_id}", @processing_lock_token, nx: true, ex: PROCESSING_TTL)
  end

  def release_locks(account_id, url)
    release_processing_lock(account_id) if @processing_lock_acquired
    redis.del(self.class.deduplication_key(account_id, url)) unless @preserve_deduplication_lock
  end

  def release_processing_lock(account_id)
    key = "drive_url_upload:processing:#{account_id}"
    redis.eval("if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end", keys: [key], argv: [@processing_lock_token])
  end

  def derived_name(url, candidate)
    File.basename(Addressable::URI.parse(url).path.to_s).presence || candidate.file_file_name
  rescue Addressable::URI::InvalidURIError
    candidate.file_file_name
  end
end
