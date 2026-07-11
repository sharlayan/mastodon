# frozen_string_literal: true

module MisskeyCompat
  module MiId
    TIME2000 = 946_684_800_000
    MIN_AID_TIME = 36**7
    SNOWFLAKE_MS_MIN = TIME2000 + MIN_AID_TIME
    FORMAT = /\A[0-9a-z]{16}\z/

    module_function

    def encode(id)
      return nil if id.nil?

      int = id.to_i
      return int.to_s if int <= 0

      ms = int >> 16
      if ms >= SNOWFLAKE_MS_MIN
        time_str = (ms - TIME2000).to_s(36)
        return "#{time_str}#{(int & 0xFFFF).to_s(36).rjust(8, '0')}" if time_str.length == 8
      end

      int.to_s(36).rjust(16, '0')
    end

    def decode(mid)
      return nil if mid.nil?

      str = mid.to_s
      return str unless str.match?(FORMAT)

      if str.start_with?('0')
        str.to_i(36).to_s
      else
        ms = str[0, 8].to_i(36) + TIME2000
        seq = str[8, 8].to_i(36)
        ((ms << 16) | seq).to_s
      end
    rescue ArgumentError
      mid.to_s
    end

    def encode_many(ids)
      Array(ids).map { |id| encode(id) }
    end

    def decode_many(mids)
      Array(mids).map { |mid| decode(mid) }
    end
  end
end
