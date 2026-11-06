# frozen_string_literal: true

module Sharlayan::PageMarkdown
  CACHE_TTL = 1.day

  def self.to_html(text)
    text = text.to_s

    Rails.cache.fetch(['sharlayan:page_markdown:v1', Digest::SHA256.hexdigest(text)], expires_in: CACHE_TTL) do
      AdvancedTextFormatter.new(text, content_type: 'text/markdown').to_s
    end
  end
end
