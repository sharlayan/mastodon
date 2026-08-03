# frozen_string_literal: true

class PageTextCharacterCounter
  class << self
    def call(summary:, content:)
      text = [summary, *collect_content_text(content)].compact.join
      text.gsub(/[[:space:]]/u, '').each_grapheme_cluster.count
    end

    private

    def collect_content_text(content)
      Array(content).flat_map do |block|
        next [] unless block.is_a?(Hash)

        case block['type'] || block[:type]
        when 'text'
          [plain_text(block['text'] || block[:text], block['format'] || block[:format])]
        when 'section'
          [block['title'] || block[:title], *collect_content_text(block['children'] || block[:children])]
        else
          []
        end
      end
    end

    def plain_text(source, format)
      source = source.to_s
      html = if format == 'markdown'
               AdvancedTextFormatter.new(source, content_type: 'text/markdown').to_s
             else
               MfmHtmlConverter.convert(source)
             end
      text = Nokogiri::HTML5.fragment(html).text
      format == 'markdown' ? text : text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\\1')
    rescue ArgumentError
      source
    end
  end
end
