# frozen_string_literal: true

module MfmHtmlConverter
  MFM_FUNC_PATTERN = /\$\[(\w+)(?:\.\S+?)?\s((?:[^\[\]]|\[(?:[^\[\]])*\])*)\]/

  BOLD_PATTERN = /\*\*(.+?)\*\*/m
  ITALIC_STAR_PATTERN = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/m
  ITALIC_UNDER_PATTERN = /_(.+?)_/m
  STRIKE_PATTERN = /~~(.+?)~~/m
  INLINE_CODE_PATTERN = /`([^`\n]+)`/
  BLOCK_CODE_PATTERN = /```(?:\w+\n)?([\s\S]+?)```/m

  EMOJI_SHORTCODE_PATTERN = /:([a-zA-Z0-9_]+):/

  HTML_TAG_PATTERN = /<[^>]*>/

  def self.convert(text)
    return '' if text.blank?

    html = text.dup

    html.gsub!(BLOCK_CODE_PATTERN) do
      "<pre><code>#{CGI.escapeHTML(::Regexp.last_match(1).strip)}</code></pre>"
    end

    html.gsub!(INLINE_CODE_PATTERN) do
      "<code>#{CGI.escapeHTML(::Regexp.last_match(1))}</code>"
    end

    emoji_map, html = extract_emojis(html)

    html.gsub!(BOLD_PATTERN) { "<b>#{::Regexp.last_match(1)}</b>" }
    html.gsub!(ITALIC_STAR_PATTERN) { "<i>#{::Regexp.last_match(1)}</i>" }
    html.gsub!(ITALIC_UNDER_PATTERN) { "<i>#{::Regexp.last_match(1)}</i>" }
    html.gsub!(STRIKE_PATTERN) { "<del>#{::Regexp.last_match(1)}</del>" }

    10.times do
      break unless html.include?('$[')

      prev = html.dup
      html = apply_mfm_functions(html)
      break if html == prev
    end

    restore_emojis(html, emoji_map)
  end

  def self.convert_in_html(html)
    return html if html.blank?

    tag_map, result = extract_tags(html)

    emoji_map, result = extract_emojis(result)

    result.gsub!(BOLD_PATTERN)        { "<b>#{::Regexp.last_match(1)}</b>" }
    result.gsub!(ITALIC_STAR_PATTERN) { "<i>#{::Regexp.last_match(1)}</i>" }
    result.gsub!(ITALIC_UNDER_PATTERN) { "<i>#{::Regexp.last_match(1)}</i>" }
    result.gsub!(STRIKE_PATTERN) { "<del>#{::Regexp.last_match(1)}</del>" }

    10.times do
      break unless result.include?('$[')

      prev = result.dup
      result = apply_mfm_functions(result)
      break if result == prev
    end

    restore_tags(restore_emojis(result, emoji_map), tag_map)
  end

  def self.extract_tags(html)
    tag_map = {}
    result = html.gsub(HTML_TAG_PATTERN) do |match|
      placeholder = "\x00t#{tag_map.size}\x00"
      tag_map[placeholder] = match
      placeholder
    end
    [tag_map, result]
  end

  def self.restore_tags(text, tag_map)
    return text if tag_map.empty?

    tag_map.each { |placeholder, original| text = text.gsub(placeholder, original) }
    text
  end

  def self.extract_emojis(text)
    emoji_map = {}
    result = text.gsub(EMOJI_SHORTCODE_PATTERN) do |match|
      placeholder = "\x00e#{emoji_map.size}\x00"
      emoji_map[placeholder] = match
      placeholder
    end
    [emoji_map, result]
  end

  def self.restore_emojis(text, emoji_map)
    return text if emoji_map.empty?

    emoji_map.each { |placeholder, original| text = text.gsub(placeholder, original) }
    text
  end

  def self.apply_mfm_functions(html)
    html.gsub(MFM_FUNC_PATTERN) do
      fn_name = ::Regexp.last_match(1)
      content = ::Regexp.last_match(2)

      case fn_name
      when 'ruby'
        parts = content.strip.split(/\s+/, 2)
        if parts.length == 2
          "<ruby>#{CGI.escapeHTML(parts[0])}<rp>(</rp><rt>#{CGI.escapeHTML(parts[1])}</rt><rp>)</rp></ruby>"
        else
          "<ruby>#{content}</ruby>"
        end
      when 'unixtime'
        ts = content.strip.to_i
        if ts.positive?
          dt = Time.at(ts).utc.iso8601
          "<time datetime=\"#{CGI.escapeHTML(dt)}\">#{CGI.escapeHTML(dt)}</time>"
        else
          content
        end
      when 'center'
        "<div style=\"text-align: center;\">#{content}</div>"
      when 'small'
        "<small>#{content}</small>"
      when 'blur'
        "<span>#{content}</span>"
      else
        "<i>#{content}</i>"
      end
    end
  end

  private_class_method :extract_emojis, :restore_emojis, :apply_mfm_functions
end
