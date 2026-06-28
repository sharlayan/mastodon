# frozen_string_literal: true

class LocalSettingsStore
  MAX_PAYLOAD_BYTES = 64.kilobytes

  class PayloadTooLarge < StandardError; end

  class << self
    def read(user_id)
      path = path_for(user_id)
      return nil unless File.exist?(path)

      json = Zlib::GzipReader.open(path, &:read)
      JSON.parse(json)
    rescue Zlib::GzipFile::Error, JSON::ParserError, EncodingError
      nil
    end

    def write(user_id, data)
      json = JSON.generate(data)
      raise PayloadTooLarge if json.bytesize > MAX_PAYLOAD_BYTES

      path = path_for(user_id)
      FileUtils.mkdir_p(File.dirname(path))

      tmp = "#{path}.#{SecureRandom.hex(8)}.tmp"
      File.open(tmp, 'wb') do |file|
        gz = Zlib::GzipWriter.new(file)
        gz.write(json)
        gz.close
      end
      FileUtils.mv(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def updated_at(user_id)
      path = path_for(user_id)
      return nil unless File.exist?(path)

      File.mtime(path).iso8601
    end

    def delete(user_id)
      FileUtils.rm_f(path_for(user_id))
    end

    private

    def base_path
      @base_path ||= ENV.fetch('LOCAL_SETTINGS_SYNC_PATH', Rails.root.join('local_settings_sync').to_s)
    end

    def path_for(user_id)
      id = user_id.to_i
      File.join(base_path, format('%03d', id % 1000), "#{id}.json.gz")
    end
  end
end
