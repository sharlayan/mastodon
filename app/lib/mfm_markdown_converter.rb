# frozen_string_literal: true

module MfmMarkdownConverter
  MFM_FUNC_PATTERN = /\$\[(\w+)(?:\.\S+?)?\s((?:[^\[\]]|\[(?:[^\[\]])*\])*)\]/

  def self.convert(text)
    return text if text.blank?

    result = text.dup

    10.times do
      break unless result.include?('$[')

      prev = result.dup
      result = unwrap_functions(result)
      break if result == prev
    end

    result
  end

  def self.unwrap_functions(text)
    text.gsub(MFM_FUNC_PATTERN) do
      fn_name = ::Regexp.last_match(1)
      content = ::Regexp.last_match(2)

      case fn_name
      when 'ruby'
        parts = content.strip.split(/\s+/, 2)
        parts.length == 2 ? "#{parts[0]}(#{parts[1]})" : content
      when 'unixtime'
        ts = content.strip.to_i
        ts.positive? ? Time.at(ts).utc.iso8601 : content
      else
        content
      end
    end
  end

  private_class_method :unwrap_functions
end
