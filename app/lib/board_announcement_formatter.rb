# frozen_string_literal: true

class BoardAnnouncementFormatter
  EXTENSIONS = {
    autolink: true,
    no_intra_emphasis: true,
    fenced_code_blocks: true,
    disable_indented_code_blocks: true,
    strikethrough: true,
    lax_spacing: true,
    space_after_headers: true,
    superscript: true,
    tables: true,
    footnotes: false,
  }.freeze

  RENDER_OPTIONS = {
    filter_html: false,
    escape_html: false,
    no_styles: false,
    safe_links_only: true,
    hard_wrap: true,
    link_attributes: { target: '_blank', rel: 'nofollow noopener' },
  }.freeze

  PRESERVE_WHITESPACE_ELEMENTS = %w(pre code).freeze

  def initialize(text)
    @text = text.to_s
  end

  def to_html
    return ''.html_safe if @text.blank?

    html = markdown.render(@text)
    html = Sanitize.fragment(html, Sanitize::Config::BOARD_ANNOUNCEMENT)
    html = strip_cosmetic_newlines(html)
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def markdown
    Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(RENDER_OPTIONS), EXTENSIONS)
  end

  def strip_cosmetic_newlines(html)
    fragment = Nokogiri::HTML5.fragment(html)

    fragment.traverse do |node|
      next unless node.text?
      next if node.ancestors.any? { |ancestor| PRESERVE_WHITESPACE_ELEMENTS.include?(ancestor.name) }

      node.content = node.content
        .gsub(/\r\n?/, "\n")
        .gsub(/\A\n+/, '')
        .gsub(/\n+\z/, '')
        .gsub(/\n+/, ' ')
    end

    fragment.to_html
  end
end
