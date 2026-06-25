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
    escape_html: true,
    no_styles: true,
    safe_links_only: true,
    hard_wrap: true,
    link_attributes: { target: '_blank', rel: 'nofollow noopener' },
  }.freeze

  def initialize(text)
    @text = text.to_s
  end

  def to_html
    return ''.html_safe if @text.blank?

    html = markdown.render(@text)
    html = Sanitize.fragment(html, Sanitize::Config::BOARD_ANNOUNCEMENT)
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def markdown
    Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(RENDER_OPTIONS), EXTENSIONS)
  end
end
