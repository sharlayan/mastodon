# frozen_string_literal: true

class BoardAnnouncementFormatter
  RENDER_FLAGS = Markly::UNSAFE | Markly::HARD_BREAKS | Markly::VALIDATE_UTF8

  EXTENSIONS = %i(table strikethrough autolink tasklist).freeze

  ALERT_TYPES = %w(note tip important warning caution).freeze
  ALERT_MARKER = /\A\[!(#{ALERT_TYPES.join('|')})\]\z/i

  PRESERVE_WHITESPACE_ELEMENTS = %w(pre code).freeze

  def initialize(text)
    @text = text.to_s
  end

  def to_html
    return ''.html_safe if @text.blank?

    html = render_markdown
    html = post_process(html)
    html = Sanitize.fragment(html, Sanitize::Config::BOARD_ANNOUNCEMENT)
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def render_markdown
    Markly.render_html(@text, flags: RENDER_FLAGS, extensions: EXTENSIONS)
  end

  def post_process(html)
    fragment = Nokogiri::HTML5.fragment(html)

    decorate_alerts(fragment)
    decorate_task_lists(fragment)
    strip_cosmetic_newlines(fragment)

    fragment.to_html
  end

  def decorate_alerts(fragment)
    fragment.css('blockquote').each do |blockquote|
      type = alert_type(blockquote)
      next if type.nil?

      strip_alert_marker(blockquote.element_children.first)

      blockquote.name = 'div'
      blockquote.remove_attribute('cite')
      blockquote['class'] = "markdown-alert markdown-alert-#{type}"

      title = Nokogiri::XML::Node.new('p', blockquote.document)
      title['class'] = 'markdown-alert-title'
      title.content = type.capitalize
      blockquote.prepend_child(title)
    end
  end

  def alert_type(blockquote)
    paragraph = blockquote.element_children.first
    return if paragraph.nil? || paragraph.name != 'p'

    marker = paragraph.children.first
    return unless marker&.text?

    match = ALERT_MARKER.match(marker.content.strip)
    match && match[1].downcase
  end

  def strip_alert_marker(paragraph)
    marker = paragraph.children.first
    following = marker.next_sibling

    marker.remove
    following.remove if following&.element? && following.name == 'br'

    paragraph.remove if paragraph.children.empty? || paragraph.text.blank?
  end

  def decorate_task_lists(fragment)
    fragment.css('input[type="checkbox"]').each do |checkbox|
      item = checkbox.parent
      next if item.nil? || item.name != 'li'

      append_class(item, 'task-list-item')
      append_class(item.parent, 'contains-task-list') if item.parent&.element?
    end
  end

  def append_class(node, name)
    classes = node['class'].to_s.split
    return if classes.include?(name)

    node['class'] = (classes << name).join(' ')
  end

  def strip_cosmetic_newlines(fragment)
    fragment.xpath('.//text()').each do |node|
      next if node.ancestors.any? { |ancestor| PRESERVE_WHITESPACE_ELEMENTS.include?(ancestor.name) }

      content = node.content.gsub(/\r\n?/, "\n")

      if content.include?("\n") && content.blank?
        node.remove
        next
      end

      node.content = content
        .gsub(/\A\n+/, '')
        .gsub(/\n+\z/, '')
        .gsub(/\n+/, ' ')
    end
  end
end
