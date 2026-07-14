# frozen_string_literal: true

class DriveFileFromURLWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 3

  def perform(account_id, url, options = {})
    account = Account.find_by(id: account_id)
    return if account.nil?

    @options = options.with_indifferent_access
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
        existing.update!(folder_id: @options[:folder_id].presence) if @options[:folder_id].present?
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
    quota = Setting.drive_quota.to_i.megabytes
    return true if quota <= 0

    used = account.drive_files.sum(:storage_file_size).to_i
    used + incoming_size.to_i <= quota
  end

  def derived_name(url, candidate)
    File.basename(Addressable::URI.parse(url).path.to_s).presence || candidate.file_file_name
  rescue Addressable::URI::InvalidURIError
    candidate.file_file_name
  end
end
