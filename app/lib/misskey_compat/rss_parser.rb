# frozen_string_literal: true

class MisskeyCompat::RSSParser
  class UnrecognizedFeedError < StandardError; end

  PAGINATION_RELS = %w(self first next prev last).freeze
  BLOCK_TAG_BREAK = %r{([^\n])</?(h|br|p|ul|ol|li|blockquote|section|table|tr|div)(?:.|\n)*?>([^\n])}
  TAG = /<(?:.|\n)*?>/

  def self.parse(xml)
    new(xml).parse
  end

  def initialize(xml)
    @document = Nokogiri::XML(xml, &:nonet)
  end

  def parse
    root = @document.root
    raise UnrecognizedFeedError if root.nil?

    case qualified_name(root)
    when 'feed'
      atom_feed(root)
    when 'rdf:RDF'
      rss_feed(first(root, 'channel') || raise(UnrecognizedFeedError), children(root, 'item'))
    when 'rss'
      rss_root(root)
    else
      raise UnrecognizedFeedError
    end
  end

  private

  def rss_root(root)
    version = root['version'].to_s
    raise UnrecognizedFeedError unless version.start_with?('2') || version.include?('0.9')

    channel = first(root, 'channel') || raise(UnrecognizedFeedError)
    feed = rss_feed(channel, children(channel, 'item'))
    feed[:itunes] = itunes(channel) if version.start_with?('2') && root.namespace_definitions.any? { |ns| ns.prefix == 'itunes' }
    feed
  end

  def rss_feed(channel, items)
    feed = {}
    atom_links = children(channel, 'atom:link')
    feed[:feedUrl] = atom_links.first['href'] if atom_links.any?
    feed[:image] = rss_image(first(channel, 'image'))
    pagination = atom_links.each_with_object({}) { |link, links| links[link['rel'].to_sym] = link['href'] if PAGINATION_RELS.include?(link['rel']) }
    feed[:paginationLinks] = pagination if pagination.any?
    copy(channel, feed, [['dc:title', :title], ['title', :title], ['description', :description], ['link', :link]])
    feed[:items] = items.map { |item| rss_item(item) }
    feed.compact
  end

  def rss_image(image)
    return if image.nil? || first(image, 'url').nil?

    { link: text_of(first(image, 'link')), url: text_of(first(image, 'url')), title: text_of(first(image, 'title')) }.compact
  end

  def rss_item(node)
    item = {}
    copy(node, item, [['author', :creator], ['dc:creator', :creator], ['dc:title', :title], ['title', :title], ['link', :link], ['pubDate', :pubDate], ['summary', :summary]])
    enclosure = first(node, 'enclosure')
    item[:enclosure] = rss_enclosure(enclosure) if enclosure
    description = first(node, 'description')
    if description
      item[:content] = text_of(description)
      item[:contentSnippet] = snippet(item[:content])
    end
    guid = first(node, 'guid')
    item[:guid] = text_of(guid) if guid
    categories = children(node, 'category')
    item[:categories] = categories.map { |category| text_of(category) } if categories.any?
    with_iso_date(item, item[:pubDate] || text_of(first(node, 'dc:date')))
  end

  def rss_enclosure(node)
    length = node['length'].to_s
    { url: node['url'].to_s, length: length.match?(/\A\d+\z/) ? length.to_i : nil, type: node['type'] }.compact
  end

  def itunes(channel)
    data = {}
    owner = first(channel, 'itunes:owner')
    data[:owner] = { name: text_of(first(owner, 'itunes:name')), email: text_of(first(owner, 'itunes:email')) }.compact if owner
    image = first(channel, 'itunes:image')
    data[:image] = image['href'] if image && image['href'].present?
    categories = children(channel, 'itunes:category')
    data[:categories] = categories.pluck('text') if categories.any?
    keywords = itunes_keywords(children(channel, 'itunes:keywords'))
    data[:keywords] = keywords unless keywords.nil?
    copy(channel, data, [['itunes:author', :author], ['itunes:summary', :summary], ['itunes:explicit', :explicit]])
    data
  end

  def itunes_keywords(nodes)
    return if nodes.empty?
    return nodes.pluck('text') if nodes.size > 1

    value = nodes.first['text'].presence || text_of(nodes.first)
    value&.split(',')
  end

  def atom_feed(root)
    feed = {}
    links = children(root, 'link')
    if links.any?
      feed[:link] = link_with_rel(links, 'alternate', 0)
      feed[:feedUrl] = link_with_rel(links, 'self', 1)
    end
    title = text_of(first(root, 'title'))
    feed[:title] = title if title.present?
    feed[:items] = children(root, 'entry').map { |entry| atom_item(entry) }
    feed.compact
  end

  def atom_item(entry)
    item = {}
    title = text_of(first(entry, 'title'))
    item[:title] = title if title.present?
    links = children(entry, 'link')
    item[:link] = link_with_rel(links, 'alternate', 0) if links.any?
    item[:pubDate] = iso_date(text_of(first(entry, 'published')).presence || text_of(first(entry, 'updated')).presence)
    author = first(entry, 'author')
    item[:creator] = text_of(first(author, 'name')) if author && first(author, 'name')
    content = first(entry, 'content')
    if content
      item[:content] = text_of(content)
      item[:contentSnippet] = snippet(item[:content])
    end
    summary = first(entry, 'summary')
    item[:summary] = text_of(summary) if summary
    id = first(entry, 'id')
    item[:guid] = text_of(id) if id
    with_iso_date(item.compact, item[:pubDate])
  end

  def link_with_rel(links, rel, fallback_index)
    link = links.find { |candidate| candidate['rel'] == rel } || links[fallback_index]
    link&.[]('href')
  end

  def copy(node, destination, fields)
    fields.each do |from, to|
      source = first(node, from)
      destination[to] = text_of(source) if source
    end
  end

  def with_iso_date(item, date)
    iso = iso_date(date)
    item[:isoDate] = iso if iso
    item
  end

  def iso_date(value)
    return if value.blank?

    time = Time.zone.parse(value.strip)
    time&.utc&.iso8601(3)
  rescue ArgumentError, RangeError
    nil
  end

  def text_of(node)
    return if node.nil?

    node.element_children.any? ? node.children.to_xml : node.text
  end

  def snippet(html)
    stripped = html.to_s.gsub(BLOCK_TAG_BREAK, "\\1\n\\3").gsub(TAG, '')
    HTMLEntities.new.decode(stripped).strip
  end

  def first(node, name)
    return if node.nil?

    node.element_children.find { |child| qualified_name(child) == name }
  end

  def children(node, name)
    node.element_children.select { |child| qualified_name(child) == name }
  end

  def qualified_name(node)
    prefix = node.namespace&.prefix
    prefix.present? ? "#{prefix}:#{node.name}" : node.name
  end
end
