# frozen_string_literal: true

class RemoteMediaDownloadBudget
  BYTE_LIMIT = (ENV['MAX_REMOTE_STATUS_MEDIA_SIZE'] || 400.megabytes).to_i
  TIME_LIMIT = (ENV['MAX_REMOTE_STATUS_MEDIA_DOWNLOAD_TIME'] || 60).to_i

  def initialize(byte_limit: BYTE_LIMIT, time_limit: TIME_LIMIT, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @remaining_bytes = byte_limit
    @clock = clock
    @deadline = @clock.call + time_limit
  end

  def available?
    @remaining_bytes.positive? && @clock.call < @deadline
  end

  def size_limit(file_limit)
    [file_limit, @remaining_bytes].min
  end

  def consume(bytes)
    @remaining_bytes = [@remaining_bytes - bytes.to_i, 0].max
  end

  def charge_download(limit, url, stored_bytes)
    attempted = url.to_s.match?(%r{\Ahttps?://}i)
    consume(stored_bytes.to_i.positive? || !attempted ? stored_bytes : limit)
  end
end
